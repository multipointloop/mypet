#include "win32_key_hook.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <cctype>
#include <cstdio>
#include <map>
#include <memory>
#include <set>
#include <string>

namespace mypet {
namespace {

flutter::MethodChannel<flutter::EncodableValue>* g_channel = nullptr;
HHOOK g_hook = nullptr;
std::set<DWORD> g_held;  // keys currently down, for repeat suppression

std::string VkName(DWORD vk) {
  static const std::map<DWORD, std::string> named = {
      {VK_SPACE, "Space"},       {VK_RETURN, "Enter"},
      {VK_ESCAPE, "Escape"},     {VK_BACK, "Backspace"},
      {VK_TAB, "Tab"},           {VK_CAPITAL, "CapsLock"},
      {VK_SHIFT, "Shift"},       {VK_LSHIFT, "Shift"},
      {VK_RSHIFT, "Shift"},      {VK_CONTROL, "Ctrl"},
      {VK_LCONTROL, "Ctrl"},     {VK_RCONTROL, "Ctrl"},
      {VK_MENU, "Alt"},          {VK_LMENU, "Alt"},
      {VK_RMENU, "Alt"},         {VK_UP, "ArrowUp"},
      {VK_DOWN, "ArrowDown"},    {VK_LEFT, "ArrowLeft"},
      {VK_RIGHT, "ArrowRight"},  {VK_DELETE, "Delete"},
      {VK_HOME, "Home"},         {VK_END, "End"},
      {VK_PRIOR, "PageUp"},      {VK_NEXT, "PageDown"},
      {VK_INSERT, "Insert"},     {VK_LWIN, "Win"},
      {VK_RWIN, "Win"},
  };
  auto it = named.find(vk);
  if (it != named.end()) return it->second;

  const UINT c = MapVirtualKeyW(vk, MAPVK_VK_TO_CHAR);
  if (c >= 'a' && c <= 'z') return std::string(1, static_cast<char>(std::toupper(c)));
  if (c >= 'A' && c <= 'Z') return std::string(1, static_cast<char>(c));
  if (c >= '0' && c <= '9') return std::string(1, static_cast<char>(c));

  char buf[16];
  std::snprintf(buf, sizeof(buf), "VK%02X", static_cast<unsigned>(vk));
  return buf;
}

LRESULT CALLBACK KeyProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode == HC_ACTION && g_channel) {
    const auto* info = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lParam);
    // ignore programmatic injections so we never echo our own UI events
    if (!(info->flags & LLKHF_INJECTED)) {
      const bool down = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);
      bool report = false;
      if (down) {
        report = g_held.insert(info->vkCode).second;  // suppress auto-repeat
      } else {
        report = g_held.erase(info->vkCode) > 0;
      }
      if (report) {
        flutter::EncodableMap args{
            {"name", VkName(info->vkCode)},
            {"vk", static_cast<int>(info->vkCode)},
            {"down", down},
        };
        g_channel->InvokeMethod("onKey",
                                std::make_unique<flutter::EncodableValue>(args));
      }
    }
  }
  return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

}  // namespace

void AttachChannel(void* channel) {
  g_channel = reinterpret_cast<
      flutter::MethodChannel<flutter::EncodableValue>*>(channel);
}

void SetKeyHookEnabled(bool enabled) {
  if (enabled && g_hook == nullptr) {
    g_hook = SetWindowsHookExW(WH_KEYBOARD_LL, KeyProc,
                               GetModuleHandleW(nullptr), 0);
  } else if (!enabled && g_hook != nullptr) {
    UnhookWindowsHookEx(g_hook);
    g_hook = nullptr;
    g_held.clear();
  }
}

void RegisterPetHotkeys(HWND hwnd) {
  RegisterHotKey(hwnd, 0, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_UP);
  RegisterHotKey(hwnd, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_DOWN);
  // Ctrl+Alt+T toggles click-through - the escape hatch when the window
  // itself ignores every mouse click
  RegisterHotKey(hwnd, 2, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'T');
  // Ctrl+Alt+S opens the settings window
  RegisterHotKey(hwnd, 3, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'S');
}

void OnHotkey(int id) {
  if (g_channel == nullptr) return;
  flutter::EncodableMap args{{"id", id}};
  g_channel->InvokeMethod("onHotkey",
                          std::make_unique<flutter::EncodableValue>(args));
}

// ---------------- per-region hit testing ----------------

struct HitTestRegions {
  bool full_passthrough = false;
  bool has = false;
  RECT pet{};    // window-local, physical px
  RECT button{}; // window-local, physical px
  RECT band{};   // speech-bubble strip (may be empty)
  bool band_on = false;
};
HitTestRegions g_hit;

HWND g_main_window = nullptr;

// Shape the window so that, outside these rects, it does not exist for the
// input system (works across processes, unlike HTTRANSPARENT).
void ApplyWindowRegion() {
  if (g_main_window == nullptr || !g_hit.has) return;
  HRGN rgn = CreateRectRgn(0, 0, 0, 0);
  if (rgn == nullptr) return;
  if (g_hit.full_passthrough) {
    HRGN button = CreateRectRgn(g_hit.button.left, g_hit.button.top,
                                g_hit.button.right, g_hit.button.bottom);
    CombineRgn(rgn, button, nullptr, RGN_COPY);
    DeleteObject(button);
  } else {
    HRGN pet = CreateRectRgn(g_hit.pet.left, g_hit.pet.top, g_hit.pet.right,
                             g_hit.pet.bottom);
    CombineRgn(rgn, rgn, pet, RGN_OR);
    DeleteObject(pet);
    HRGN button = CreateRectRgn(g_hit.button.left, g_hit.button.top,
                                g_hit.button.right, g_hit.button.bottom);
    CombineRgn(rgn, rgn, button, RGN_OR);
    DeleteObject(button);
    if (g_hit.band_on) {
      HRGN band = CreateRectRgn(g_hit.band.left, g_hit.band.top,
                                g_hit.band.right, g_hit.band.bottom);
      CombineRgn(rgn, rgn, band, RGN_OR);
      DeleteObject(band);
    }
  }
  // The window owns the region afterwards; no DeleteObject here.
  SetWindowRgn(g_main_window, rgn, TRUE);
}

void AttachMainWindow(HWND hwnd) { g_main_window = hwnd; }

void SetHitTestRegions(bool full_passthrough, const RECT& pet,
                       const RECT& button, const RECT& band, bool band_on) {
  g_hit.full_passthrough = full_passthrough;
  g_hit.pet = pet;
  g_hit.button = button;
  g_hit.band = band;
  g_hit.band_on = band_on;
  g_hit.has = true;
  ApplyWindowRegion();
}

LRESULT HandleNCHitTest(HWND hwnd, LPARAM lparam) {
  if (!g_hit.has) return HTCLIENT;
  POINT pt;
  pt.x = static_cast<short>(LOWORD(lparam));
  pt.y = static_cast<short>(HIWORD(lparam));
  ScreenToClient(hwnd, &pt);
  // the toggle button stays clickable in every mode
  if (PtInRect(&g_hit.button, pt)) return HTCLIENT;
  if (g_hit.full_passthrough) return HTTRANSPARENT;
  // the pet body is interactive; the transparent rest of the window lets
  // clicks through to whatever the user is working on
  if (PtInRect(&g_hit.pet, pt)) return HTCLIENT;
  return HTTRANSPARENT;
}

// ---------------- native tray quick menu ----------------

constexpr UINT kQuickMenuBase = 4000;

void ShowQuickMenu() {
  HWND hwnd = g_main_window;
  if (hwnd == nullptr) return;
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, kQuickMenuBase + 0, L"\u653E\u5927   (Ctrl+Alt+Up)");
  AppendMenuW(menu, MF_STRING, kQuickMenuBase + 1, L"\u7F29\u5C0F   (Ctrl+Alt+Down)");
  AppendMenuW(menu, MF_STRING, kQuickMenuBase + 2, L"\u9F20\u6807\u7A7F\u900F (Ctrl+Alt+T)");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kQuickMenuBase + 3, L"\u8BBE\u7F6E\u9762\u677F (Ctrl+Alt+S)");
  AppendMenuW(menu, MF_STRING, kQuickMenuBase + 4, L"\u9000\u51FA MyPet");
  POINT pt{};
  GetCursorPos(&pt);
  // TrackPopupMenu needs a foreground owner and a WM_NULL afterwards,
  // otherwise the menu is dismissed by the next input event.
  SetForegroundWindow(hwnd);
  const int cmd =
      TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY,
                     pt.x, pt.y, 0, hwnd, nullptr);
  PostMessage(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (cmd >= static_cast<int>(kQuickMenuBase) && g_channel != nullptr) {
    flutter::EncodableMap args{{"id", cmd - static_cast<int>(kQuickMenuBase)}};
    g_channel->InvokeMethod("onQuickMenu",
                            std::make_unique<flutter::EncodableValue>(args));
  }
}

// ---------------- Flutter child view subclassing ----------------

WNDPROC g_childProc = nullptr;

LRESULT CALLBACK ChildViewProc(HWND hwnd, UINT message, WPARAM wparam,
                               LPARAM lparam) {
  if (message == WM_NCHITTEST) {
    return HandleNCHitTest(hwnd, lparam);
  }
  return CallWindowProc(g_childProc, hwnd, message, wparam, lparam);
}

void SubclassFlutterView(HWND hwnd) {
  g_childProc = reinterpret_cast<WNDPROC>(
      SetWindowLongPtrW(hwnd, GWLP_WNDPROC,
                        reinterpret_cast<LONG_PTR>(ChildViewProc)));
}

}  // namespace mypet
