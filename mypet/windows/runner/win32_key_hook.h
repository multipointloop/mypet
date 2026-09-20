#ifndef RUNNER_WIN32_KEY_HOOK_H_
#define RUNNER_WIN32_KEY_HOOK_H_

#include <windows.h>

namespace mypet {

// Stores the Dart method channel used to push events back into Flutter.
// Raw pointer is fine: the channel is owned by FlutterWindow and outlives
// every hook callback.
void AttachChannel(void* channel);

// Installs / removes the global WH_KEYBOARD_LL hook. OFF by default; the
// Flutter settings page (and tray) control it explicitly because a global
// keyboard hook can trigger antivirus prompts and is unwelcome inside
// games with anti-cheat.
void SetKeyHookEnabled(bool enabled);

// Registers Ctrl+Alt+Up (id 0), Ctrl+Alt+Down (id 1), Ctrl+Alt+T (id 2).
void RegisterPetHotkeys(HWND hwnd);

// Call from the window message handler on WM_HOTKEY.
void OnHotkey(int id);

// ---- per-region hit testing + window region -----------------------------
//
// WM_NCHITTEST / HTTRANSPARENT only forwards clicks to windows IN THE SAME
// THREAD, so it can never let clicks reach the taskbar or other apps. The
// window is therefore also SHAPED with SetWindowRgn: outside the region the
// window does not exist for the input system, which works across processes.
//
// Dart pushes window-local PHYSICAL pixel rects:
//   pet    - the drawn pet body (clickable & draggable)
//   button - the click-through toggle button (ALWAYS clickable, even in
//            full-passthrough mode, so the user can never get stuck)
//   band   - the speech-bubble strip above the pet; kept inside the region so
//            a bubble is never clipped (band_on = a bubble is visible)
//
// Region rules: full_passthrough -> button only; else pet + button (+ band).
void SetHitTestRegions(bool full_passthrough, const RECT& pet,
                       const RECT& button, const RECT& band, bool band_on);
LRESULT HandleNCHitTest(HWND hwnd, LPARAM lparam);

// Top-level window handle - the target of SetWindowRgn.
void AttachMainWindow(HWND hwnd);

// The Flutter view lives in a CHILD window that covers the whole client
// area and is hit-tested BEFORE the parent - the parent-level WM_NCHITTEST
// never sees pet vs background. Subclassing the child routes its
// WM_NCHITTEST through the same region logic.
void SubclassFlutterView(HWND hwnd);

}  // namespace mypet

#endif  // RUNNER_WIN32_KEY_HOOK_H_
