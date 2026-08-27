option casemap:none

EXTERN MoreDropsEchoGateTarget:PROC
PUBLIC MoreDropsEchoAppendGate

.code
MoreDropsEchoAppendGate PROC
    sub rsp, 20h
    lea rcx, [rbp-60h]
    call MoreDropsEchoGateTarget
    add rsp, 20h
    jmp rax
MoreDropsEchoAppendGate ENDP
END
