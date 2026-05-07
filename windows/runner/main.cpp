#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr unsigned int kDefaultWindowWidth = 1510;
constexpr unsigned int kDefaultWindowHeight = 870;
constexpr unsigned int kMinimumWindowWidth = 960;
constexpr unsigned int kMinimumWindowHeight = 640;
constexpr LONG kHorizontalMargin = 80;
constexpr LONG kVerticalMargin = 80;

Win32Window::Size ResolveInitialWindowSize() {
  const Win32Window::Size fallback_size(
      kDefaultWindowWidth, kDefaultWindowHeight);

  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFO);
  const HMONITOR monitor =
      MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  if (monitor == nullptr || !GetMonitorInfo(monitor, &monitor_info)) {
    return fallback_size;
  }

  const RECT work_area = monitor_info.rcWork;
  const LONG work_area_width = work_area.right - work_area.left;
  const LONG work_area_height = work_area.bottom - work_area.top;

  const LONG width = std::min<LONG>(
      kDefaultWindowWidth,
      std::max<LONG>(work_area_width - kHorizontalMargin, kMinimumWindowWidth));
  const LONG height = std::min<LONG>(
      kDefaultWindowHeight,
      std::max<LONG>(work_area_height - kVerticalMargin, kMinimumWindowHeight));

  return Win32Window::Size(static_cast<unsigned int>(width),
                           static_cast<unsigned int>(height));
}

Win32Window::Point ResolveInitialWindowOrigin(const Win32Window::Size& size) {
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFO);
  const HMONITOR monitor =
      MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  if (monitor == nullptr || !GetMonitorInfo(monitor, &monitor_info)) {
    return Win32Window::Point(10, 10);
  }

  const RECT work_area = monitor_info.rcWork;
  const LONG work_area_width = work_area.right - work_area.left;
  const LONG work_area_height = work_area.bottom - work_area.top;
  const LONG window_width = static_cast<LONG>(size.width);
  const LONG window_height = static_cast<LONG>(size.height);

  const LONG centered_x =
      work_area.left + std::max<LONG>(0, (work_area_width - window_width) / 2);
  const LONG centered_y =
      work_area.top + std::max<LONG>(0, (work_area_height - window_height) / 2);

  return Win32Window::Point(static_cast<unsigned int>(centered_x),
                            static_cast<unsigned int>(centered_y));
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  const Win32Window::Size size = ResolveInitialWindowSize();
  const Win32Window::Point origin = ResolveInitialWindowOrigin(size);
  if (!window.Create(L"Mise GUI", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
