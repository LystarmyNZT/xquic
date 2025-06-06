# Copyright (c) 2022, Alibaba Group Holding Limited

#!/bin/bash

function generate_cert() {
    if [[ ! -f "server.key" || ! -f "server.crt" ]]; then
        keyfile=server.key
        certfile=server.crt
        openssl req -newkey rsa:2048 -x509 -nodes -keyout "$keyfile" -new -out "$certfile" -subj /CN=test.xquic.com
    fi
}

function install_gcov_tool() {
    #install gcovr which can output code coverage summary
    apt-get install -y python3-pip > /dev/null
    apt-get install -y python3-lxml > /dev/null
    apt-get install -y gcovr> /dev/null
}

function install_cunit() {
    apt-get install -y libcunit1 libcunit1-doc libcunit1-dev > /dev/null
}

function install_go() {
    apt-get install -y golang
}

function build_babassl() {
    git clone https://github.com/Tongsuo-Project/Tongsuo.git ../third_party/babassl
    cd ../third_party/babassl/
    ./config --prefix=/usr/local/babassl --api=1.1.1 no-deprecated
    make -j
    SSL_PATH_STR="${PWD}"
    cd -
}

function build_boringssl() {
    git clone https://github.com/google/boringssl.git ../third_party/boringssl
    mkdir -p ../third_party/boringssl/build
    cd ../third_party/boringssl/build
    cmake -DBUILD_SHARED_LIBS=0 -DCMAKE_C_FLAGS="-fPIC" -DCMAKE_CXX_FLAGS="-fPIC" ..
    make ssl crypto
    cd ..
    SSL_PATH_STR="${PWD}"
    cd ../../build/
}

function do_compile() {
    rm -f CMakeCache.txt
    if [[ $1 == "boringssl" ]]; then
        build_boringssl
        SSL_TYPE_STR="boringssl"

    else
        build_babassl
        SSL_TYPE_STR="babassl"
    fi

    #turn on Code Coverage
    cmake -DGCOV=on -DCMAKE_BUILD_TYPE=Debug -DXQC_ENABLE_TESTING=1 -DXQC_PRINT_SECRET=1 -DXQC_SUPPORT_SENDMMSG_BUILD=1 -DXQC_ENABLE_EVENT_LOG=1 -DXQC_ENABLE_BBR2=1 -DXQC_ENABLE_RENO=1 -DSSL_TYPE=${SSL_TYPE_STR} -DSSL_PATH=${SSL_PATH_STR} -DXQC_ENABLE_UNLIMITED=1 -DXQC_ENABLE_COPA=1 -DXQC_COMPAT_DUPLICATE=1 ..
    make -j

    if [ $? -ne 0 ]; then
        echo "cmake failed"
        exit 1
    fi
    rm -f CMakeCache.txt
}

function run_test_case() {
    # "unit test..."
    ./tests/run_tests | tee -a xquic_test.log

    # "case test..."
    bash ../scripts/case_test.sh | tee -a xquic_test.log

}

function run_gcov() {
    #output coverage summary
    gcovr -r .. | tee -a xquic_test.log
}

function output_summary() {
    echo "=============summary=============="
    echo -e "unit test:"
    cat xquic_test.log | grep "Test:"
    passed=`cat xquic_test.log | grep "Test:" | grep "passed" | wc -l`
    failed=`cat xquic_test.log | grep "Test:" | grep "FAILED" | wc -l`
    echo -e "\033[32m unit test passed:$passed failed:$failed \033[0m"

    echo -e "\ncase test:"
    cat xquic_test.log | grep "pass:"
    passed=`cat xquic_test.log | grep "pass:" | grep "pass:1" | wc -l`
    failed=`cat xquic_test.log | grep "pass:" | grep "pass:0" | wc -l`
    echo -e "\033[32m case test passed:$passed failed:$failed \033[0m"

    echo -e "\nCode Coverage:                             Lines    Exec  Cover"
    cat xquic_test.log | grep "TOTAL"
}

cd ../build
mkdir -p ../third_party

> xquic_test.log


generate_cert
install_gcov_tool
install_cunit
install_go

#run boringssl
do_compile "boringssl"
run_test_case

#run babassl
do_compile
run_test_case

run_gcov
output_summary

cd -
