# WebRenderer engine library — WKWebView + WE JS API host.

add_library(WebRendererEngine STATIC
    WallpaperManifest.h
    WallpaperManifest.mm
    WRAudioTap.h
    WRAudioTap.mm
    WRURLSchemeHandler.h
    WRURLSchemeHandler.mm
    WRDesktopInputForwarder.h
    WRDesktopInputForwarder.mm
    WebRendererEngine.h
    WebRendererEngine.mm)

target_compile_features(WebRendererEngine PUBLIC cxx_std_20)
set_target_properties(WebRendererEngine PROPERTIES OBJCXX_STANDARD 20 OBJCXX_STANDARD_REQUIRED ON)
target_include_directories(WebRendererEngine PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(WebRendererEngine PUBLIC ${WR_FRAMEWORKS})

target_compile_options(WebRendererEngine PRIVATE
    -Wno-deprecated-declarations
    -Wno-unused-function)
