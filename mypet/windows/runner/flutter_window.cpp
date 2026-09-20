#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "win32_key_hook.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  // the Flutter child view is hit-tested before this top-level window, so
  // the pet-vs-background click routing must hook into ITS wndproc
  mypet::SubclassFlutterView(flutter_controller_->view()->GetNativeWindow());

  // ---- MyPet native bridge: key hook + global hotkeys ----
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "mypet/native",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "setKeyHook") {
          // Dart sends {"enabled": bool}; a bare bool is also accepted.
          // NOTE: keep all comments ASCII - MSVC without /utf-8 mis-decodes
          // multi-byte characters and can swallow the following line.
          bool hook_enabled = false;
          if (const auto* direct = std::get_if<bool>(call.arguments())) {
            hook_enabled = *direct;
          } else if (const auto* args = std::get_if<flutter::EncodableMap>(
                         call.arguments())) {
            auto it = args->find(flutter::EncodableValue("enabled"));
            if (it != args->end()) {
              if (const auto* flag = std::get_if<bool>(&it->second)) {
                hook_enabled = *flag;
              }
            }
          }
          mypet::SetKeyHookEnabled(hook_enabled);
          result->Success();
        } else if (call.method_name() == "setHitTest") {
          const auto* map = std::get_if<flutter::EncodableMap>(call.arguments());
          if (map != nullptr) {
            bool full = false;
            double pet[4] = {0, 0, 0, 0};
            double button[4] = {0, 0, 0, 0};
            auto full_it = map->find(flutter::EncodableValue("full"));
            if (full_it != map->end()) {
              if (const auto* b = std::get_if<bool>(&full_it->second)) {
                full = *b;
              }
            }
            auto read_rect = [&](const char* key, double* out) {
              auto it = map->find(flutter::EncodableValue(key));
              if (it == map->end()) return;
              if (const auto* list =
                      std::get_if<flutter::EncodableList>(&it->second)) {
                for (size_t i = 0; i < 4 && i < list->size(); ++i) {
                  if (const auto* d = std::get_if<double>(&(*list)[i])) {
                    out[i] = *d;
                  } else if (const auto* n = std::get_if<int32_t>(&(*list)[i])) {
                    out[i] = static_cast<double>(*n);
                  }
                }
              }
            };
            read_rect("pet", pet);
            read_rect("button", button);
            mypet::SetHitTestRegions(
                full,
                RECT{static_cast<LONG>(pet[0]), static_cast<LONG>(pet[1]),
                     static_cast<LONG>(pet[2]), static_cast<LONG>(pet[3])},
                RECT{static_cast<LONG>(button[0]), static_cast<LONG>(button[1]),
                     static_cast<LONG>(button[2]),
                     static_cast<LONG>(button[3])});
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  mypet::AttachChannel(channel_.get());
  mypet::RegisterPetHotkeys(GetHandle());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  mypet::SetKeyHookEnabled(false);
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Per-region hit testing must win over everything else: it decides which
  // pixels of the transparent window belong to the pet / toggle button and
  // which pass clicks through to the windows behind.
  if (message == WM_NCHITTEST) {
    return mypet::HandleNCHitTest(hwnd, lparam);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_HOTKEY:
      mypet::OnHotkey(static_cast<int>(wparam));
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
