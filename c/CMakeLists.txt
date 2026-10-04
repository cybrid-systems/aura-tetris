cmake_minimum_required(VERSION 3.16)
project(aura_tetris_viewport C)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

add_executable(tetris_play play.c)
target_compile_options(tetris_play PRIVATE -O2 -Wall -Wextra -pedantic)
