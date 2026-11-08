// Loads a dylib into another process by starting a thread in it that calls dlopen.
//
// :Attribution
// Adapted from yabai's scripting-addition loader (src/osax/loader.m), MIT License,
// Copyright (c) 2019 Åsmund Vikane — https://github.com/koekeishiya/yabai
// whose arm64e injection path is based on work by Jeremy Legendre (https://github.com/jslegendre).
// The shellcode is yabai's, unchanged; this file turns the loader into a function.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software
// and associated documentation files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions: The above copyright notice
// and this permission notice shall be included in all copies or substantial portions of the
// Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.

#include <Foundation/Foundation.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>
#include "loader.h"

#ifdef __arm64__
#include <ptrauth.h>
static kern_return_t (*_thread_convert_thread_state)(thread_act_t thread, int direction, thread_state_flavor_t flavor,
                                                     thread_state_t in_state, mach_msg_type_number_t in_stateCnt,
                                                     thread_state_t out_state, mach_msg_type_number_t *out_stateCnt);
#endif

#define DF_FAIL(...) do { snprintf(error, error_size, __VA_ARGS__); return 1; } while (0)

// Starts a pthread (pthread_create_from_mach_thread) that dlopens the path stored after the code,
// then parks the mach thread with 0x79616265 in x0/rax so the loader knows it got that far.
static const char shell_code_template[] =
#ifdef __x86_64__
"\x55"                             // push       rbp
"\x48\x89\xE5"                     // mov        rbp, rsp
"\x48\x83\xEC\x10"                 // sub        rsp, 0x10
"\x48\x8D\x7D\xF8"                 // lea        rdi, qword [rbp+var_8]
"\x31\xC0"                         // xor        eax, eax
"\x89\xC1"                         // mov        ecx, eax
"\x48\x8D\x15\x1E\x00\x00\x00"     // lea        rdx, qword ptr [rip+0x1E]
"\x48\x89\xCE"                     // mov        rsi, rcx
"\x48\xB8"                         // movabs     rax, pthread_create_from_mach_thread
"\x00\x00\x00\x00\x00\x00\x00\x00" //
"\xFF\xD0"                         // call       rax
"\x48\x83\xC4\x10"                 // add        rsp, 0x10
"\x5D"                             // pop        rbp
"\x48\xC7\xC0\x65\x62\x61\x79"     // mov        rax, 0x79616265
"\xEB\xFE"                         // jmp        0x0
"\xC3"                             // ret
"\x55"                             // push       rbp
"\x48\x89\xE5"                     // mov        rbp, rsp
"\xBE\x01\x00\x00\x00"             // mov        esi, 0x1
"\x48\x8D\x3D\x16\x00\x00\x00"     // lea        rdi, qword ptr [rip+0x16]
"\x48\xB8"                         // movabs     rax, dlopen
"\x00\x00\x00\x00\x00\x00\x00\x00" //
"\xFF\xD0"                         // call       rax
"\x31\xF6"                         // xor        esi, esi
"\x89\xF7"                         // mov        edi, esi
"\x48\x89\xF8"                     // mov        rax, rdi
"\x5D"                             // pop        rbp
"\xC3"                             // ret
#elif __arm64__
"\xFF\xC3\x00\xD1"                 // sub        sp, sp, #0x30
"\xFD\x7B\x02\xA9"                 // stp        x29, x30, [sp, #0x20]
"\xFD\x83\x00\x91"                 // add        x29, sp, #0x20
"\xA0\xC3\x1F\xB8"                 // stur       w0, [x29, #-0x4]
"\xE1\x0B\x00\xF9"                 // str        x1, [sp, #0x10]
"\xE0\x23\x00\x91"                 // add        x0, sp, #0x8
"\x08\x00\x80\xD2"                 // mov        x8, #0
"\xE8\x07\x00\xF9"                 // str        x8, [sp, #0x8]
"\xE1\x03\x08\xAA"                 // mov        x1, x8
"\xE2\x01\x00\x10"                 // adr        x2, #0x3C
"\xE2\x23\xC1\xDA"                 // paciza     x2
"\xE3\x03\x08\xAA"                 // mov        x3, x8
"\x49\x01\x00\x10"                 // adr        x9, #0x28 ; pthread_create_from_mach_thread
"\x29\x01\x40\xF9"                 // ldr        x9, [x9]
"\x20\x01\x3F\xD6"                 // blr        x9
"\xA0\x4C\x8C\xD2"                 // movz       x0, #0x6265
"\x20\x2C\xAF\xF2"                 // movk       x0, #0x7961, lsl #16
"\x09\x00\x00\x10"                 // adr        x9, #0
"\x20\x01\x1F\xD6"                 // br         x9
"\xFD\x7B\x42\xA9"                 // ldp        x29, x30, [sp, #0x20]
"\xFF\xC3\x00\x91"                 // add        sp, sp, #0x30
"\xC0\x03\x5F\xD6"                 // ret
"\x00\x00\x00\x00\x00\x00\x00\x00" //
"\x7F\x23\x03\xD5"                 // pacibsp
"\xFF\xC3\x00\xD1"                 // sub        sp, sp, #0x30
"\xFD\x7B\x02\xA9"                 // stp        x29, x30, [sp, #0x20]
"\xFD\x83\x00\x91"                 // add        x29, sp, #0x20
"\xA0\xC3\x1F\xB8"                 // stur       w0, [x29, #-0x4]
"\xE1\x0B\x00\xF9"                 // str        x1, [sp, #0x10]
"\x21\x00\x80\xD2"                 // mov        x1, #1
"\x60\x01\x00\x10"                 // adr        x0, #0x2c ; payload_path
"\x09\x01\x00\x10"                 // adr        x9, #0x20 ; dlopen
"\x29\x01\x40\xF9"                 // ldr        x9, [x9]
"\x20\x01\x3F\xD6"                 // blr        x9
"\x09\x00\x80\x52"                 // mov        w9, #0
"\xE0\x03\x09\xAA"                 // mov        x0, x9
"\xFD\x7B\x42\xA9"                 // ldp        x29, x30, [sp, #0x20]
"\xFF\xC3\x00\x91"                 // add        sp, sp, #0x30
"\xFF\x0F\x5F\xD6"                 // retab
"\x00\x00\x00\x00\x00\x00\x00\x00" //
#endif
"\x00\x00\x00\x00\x00\x00\x00\x00" // empty space for payload_path
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00";

#ifdef __x86_64__
enum { DF_PCFMT_OFFSET = 28, DF_DLOPEN_OFFSET = 71, DF_PATH_OFFSET = 90 };
#elif __arm64__
enum { DF_PCFMT_OFFSET = 88, DF_DLOPEN_OFFSET = 160, DF_PATH_OFFSET = 168 };
#endif

int df_inject(pid_t pid, const char *payload_path, char *error, size_t error_size) {
    mach_port_t task = 0;
    thread_act_t thread = 0;
    mach_vm_address_t code = 0;
    mach_vm_address_t stack = 0;
    vm_size_t stack_size = 16 * 1024;
    uint64_t stack_contents = 0x00000000CAFEBABE;
    char shell_code[sizeof(shell_code_template)];
    memcpy(shell_code, shell_code_template, sizeof(shell_code));

    if (strlen(payload_path) + 1 > sizeof(shell_code) - DF_PATH_OFFSET) DF_FAIL("payload path too long");
    if (task_for_pid(mach_task_self(), pid, &task) != KERN_SUCCESS)
        DF_FAIL("could not get the Dock's task port (needs root, and SIP's debugging restrictions off)");
    if (mach_vm_allocate(task, &stack, stack_size, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) DF_FAIL("could not allocate stack");
    if (mach_vm_write(task, stack, (vm_address_t)&stack_contents, sizeof(uint64_t)) != KERN_SUCCESS) DF_FAIL("could not write stack");
    if (vm_protect(task, stack, stack_size, 1, VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS) DF_FAIL("could not protect stack");
    if (mach_vm_allocate(task, &code, sizeof(shell_code), VM_FLAGS_ANYWHERE) != KERN_SUCCESS) DF_FAIL("could not allocate code");

#ifdef __x86_64__
    uint64_t pcfmt_address = (uint64_t)dlsym(RTLD_DEFAULT, "pthread_create_from_mach_thread");
    uint64_t dlopen_address = (uint64_t)dlsym(RTLD_DEFAULT, "dlopen");
#elif __arm64__
    uint64_t pcfmt_address = (uint64_t)ptrauth_strip(dlsym(RTLD_DEFAULT, "pthread_create_from_mach_thread"), ptrauth_key_function_pointer);
    uint64_t dlopen_address = (uint64_t)ptrauth_strip(dlsym(RTLD_DEFAULT, "dlopen"), ptrauth_key_function_pointer);
#endif
    memcpy(shell_code + DF_PCFMT_OFFSET, &pcfmt_address, sizeof(uint64_t));
    memcpy(shell_code + DF_DLOPEN_OFFSET, &dlopen_address, sizeof(uint64_t));
    memcpy(shell_code + DF_PATH_OFFSET, payload_path, strlen(payload_path));

    if (mach_vm_write(task, code, (vm_address_t)shell_code, sizeof(shell_code)) != KERN_SUCCESS) DF_FAIL("could not write code");
    if (vm_protect(task, code, sizeof(shell_code), 0, VM_PROT_EXECUTE | VM_PROT_READ) != KERN_SUCCESS) DF_FAIL("could not protect code");

    kern_return_t kr;
#ifdef __x86_64__
    x86_thread_state64_t thread_state = {};
    thread_state_flavor_t thread_flavor = x86_THREAD_STATE64;
    mach_msg_type_number_t thread_flavor_count = x86_THREAD_STATE64_COUNT;
    thread_state.__rip = (uint64_t)code;
    thread_state.__rsp = (uint64_t)stack + (stack_size / 2);
    kr = thread_create_running(task, thread_flavor, (thread_state_t)&thread_state, thread_flavor_count, &thread);
    if (kr != KERN_SUCCESS) DF_FAIL("could not start thread: %s", mach_error_string(kr));
#elif __arm64__
    void *handle = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_GLOBAL | RTLD_LAZY);
    if (handle) {
        _thread_convert_thread_state = dlsym(handle, "thread_convert_thread_state");
        dlclose(handle);
    }
    if (!_thread_convert_thread_state) DF_FAIL("missing thread_convert_thread_state");

    arm_thread_state64_t thread_state = {}, machine_thread_state = {};
    thread_state_flavor_t thread_flavor = ARM_THREAD_STATE64;
    mach_msg_type_number_t thread_flavor_count = ARM_THREAD_STATE64_COUNT, machine_thread_flavor_count = ARM_THREAD_STATE64_COUNT;
    __darwin_arm_thread_state64_set_pc_fptr(thread_state, ptrauth_sign_unauthenticated((void *)code, ptrauth_key_asia, 0));
    __darwin_arm_thread_state64_set_sp(thread_state, stack + (stack_size / 2));

    kr = thread_create(task, &thread);
    if (kr != KERN_SUCCESS) DF_FAIL("could not create thread: %s", mach_error_string(kr));
    kr = _thread_convert_thread_state(thread, 2, thread_flavor, (thread_state_t)&thread_state, thread_flavor_count,
                                      (thread_state_t)&machine_thread_state, &machine_thread_flavor_count);
    if (kr != KERN_SUCCESS) DF_FAIL("could not convert thread state: %s", mach_error_string(kr));

    // macOS 14.4 and later: start a fresh thread with the converted state.
    thread_terminate(thread);
    kr = thread_create_running(task, thread_flavor, (thread_state_t)&machine_thread_state, machine_thread_flavor_count, &thread);
    if (kr != KERN_SUCCESS) DF_FAIL("could not start thread: %s", mach_error_string(kr));
#endif

    usleep(10000);
    int result = 1;
    snprintf(error, error_size, "the Dock didn't confirm loading");
    for (int i = 0; i < 10; ++i) {
        kr = thread_get_state(thread, thread_flavor, (thread_state_t)&thread_state, &thread_flavor_count);
        if (kr != KERN_SUCCESS) { snprintf(error, error_size, "lost the thread: %s", mach_error_string(kr)); break; }
#ifdef __x86_64__
        if (thread_state.__rax == 0x79616265) { result = 0; break; }
#elif __arm64__
        if (thread_state.__x[0] == 0x79616265) { result = 0; break; }
#endif
        usleep(20000);
    }
    thread_terminate(thread);
    if (result == 0) error[0] = 0;
    return result;
}
