#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DIR="$(readlink -f $DIR/..)"

cmake -G "Ninja Multi-Config" \
      -DLLVM_DIR=$LLVM_DIR -DClang_DIR=$Clang_DIR \
      -DBUILD_SHARED_LIBS=NO \
      -DWITH_TESTS=NO -DWITH_APPS=NO -DWITH_TUTORIALS=NO \
      -DWITH_DOCS=YES -DWITH_UTILS=NO -DWITH_PYTHON_BINDINGS=NO \
      -S "$DIR" -B "$DIR/build/static"

cmake -G "Ninja Multi-Config" \
      -DLLVM_DIR=$LLVM_DIR -DClang_DIR=$Clang_DIR \
      -DBUILD_SHARED_LIBS=YES \
      -DWITH_TESTS=NO -DWITH_APPS=NO -DWITH_TUTORIALS=NO \
      -DWITH_DOCS=YES -DWITH_UTILS=NO -DWITH_PYTHON_BINDINGS=NO \
      -S "$DIR" -B "$DIR/build/shared"

cmake --build "$DIR/build/shared" --config Debug
cmake --build "$DIR/build/shared" --config Release 
cmake --build "$DIR/build/static" --config Debug
cmake --build "$DIR/build/static" --config Release 

cmake --install "$DIR/build/shared" --prefix "$DIR/build/install" --config Debug
cmake --install "$DIR/build/shared" --prefix "$DIR/build/install" --config Release 
cmake --install "$DIR/build/static" --prefix "$DIR/build/install" --config Debug
cmake --install "$DIR/build/static" --prefix "$DIR/build/install" --config Release

