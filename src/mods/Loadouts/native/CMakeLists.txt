cmake_minimum_required(VERSION 3.22)
project(LoadoutsEventRelay LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")

add_library(LoadoutsEventRelay SHARED dllmain.cpp)
target_compile_definitions(LoadoutsEventRelay PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    $<$<CONFIG:Debug>:LOADOUTS_DEBUG_CONFIGURATION>
)
