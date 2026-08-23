cmake_minimum_required(VERSION 3.22)
project(MorePlayersSteamLimit LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")

include(FetchContent)
FetchContent_Declare(minhook
  GIT_REPOSITORY https://github.com/TsudaKageyu/minhook.git
  GIT_TAG v1.3.4)
FetchContent_MakeAvailable(minhook)

add_library(MorePlayersSteamLimit SHARED dllmain.cpp)
target_link_libraries(MorePlayersSteamLimit PRIVATE minhook)
target_compile_definitions(MorePlayersSteamLimit PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)

