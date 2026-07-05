add_executable(VideoViewer VideoViewer.mm)

target_link_libraries(VideoViewer PRIVATE
    VideoRendererEngine
    ${VR_FRAMEWORKS})

target_compile_features(VideoViewer PRIVATE cxx_std_20)
set_target_properties(VideoViewer PROPERTIES
    OBJCXX_STANDARD 20
    OBJCXX_STANDARD_REQUIRED ON)
target_compile_options(VideoViewer PRIVATE -Wno-deprecated-declarations)
