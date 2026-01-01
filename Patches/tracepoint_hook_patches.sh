#!/usr/bin/env bash
# Patches author: ShirkNeko @ Github
#                 backslashxx @ Github
# Shell authon: JackA1ltman <cs2dtzq@163.com>
# Tested kernel versions: 5.4, 4.19, 4.14, 4.9, 4.4, 3.18
# 20250821

patch_files=(
    fs/exec.c
    fs/open.c
    fs/read_write.c
    fs/stat.c
    fs/namei.c
    drivers/input/input.c
    security/security.c
    security/selinux/hooks.c
    kernel/reboot.c
    kernel/sys.c
)

PATCH_LEVEL="1.1"
KERNEL_VERSION=$(head -n 3 Makefile | grep -E 'VERSION|PATCHLEVEL' | awk '{print $3}' | paste -sd '.')
FIRST_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $1}')
SECOND_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $2}')

echo "Current tracepoint patch version:$PATCH_LEVEL"

for i in "${patch_files[@]}"; do

    if grep -q "trace_ksu" "$i"; then
        echo "[-] Warning: $i contains KernelSU"
        echo "[+] Code in here:"
        grep -n "trace_ksu" "$i"
        echo "[-] End of file."
        echo "======================================"
        continue
    fi

    case $i in

    # fs/ changes
    ## exec.c
    fs/exec.c)
        echo "======================================"

        sed -i '/#include <trace\/events\/sched.h>/a \#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)\n#include <..\/drivers\/kernelsu\/ksu_trace.h>\n#endif' fs/exec.c
        if grep -q "do_execveat_common" fs/exec.c; then
            awk '
/return do_execveat_common\(AT_FDCWD, filename, argv, envp, 0\);/ {
    count++;
    if (count == 1) {
        print "#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)";
        print "\ttrace_ksu_trace_execveat_hook((int *)AT_FDCWD, &filename, &argv, &envp, 0);";
        print "#endif";
    }
}
{
    print;
}
' fs/exec.c > fs/exec.c.new
            mv fs/exec.c.new fs/exec.c
        else
awk '
/return do_execve_common\(filename, argv, envp\);/ {
    count++;
    if (count == 1) {
        print "#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)";
        print "\ttrace_ksu_trace_execveat_hook((int *)AT_FDCWD, &filename, &argv, &envp, 0);";
        print "#endif";
    }
}
{
    print;
}
' fs/exec.c > fs/exec.c.new
            mv fs/exec.c.new fs/exec.c
        fi

        if grep -q "trace_ksu_trace_execveat_hook" "fs/exec.c"; then
            echo "[+] fs/exec.c Patched!"
            echo "[+] Count: $(grep -c "trace_ksu_trace_execveat_hook" "fs/exec.c")"
        else
            echo "[-] fs/exec.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;
    ## open.c
    fs/open.c)
        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 19 ]; then
            sed -i '/#include "internal.h"/a \#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)\n#include <..\/drivers\/kernelsu\/ksu_trace.h>\n#endif' fs/open.c
            sed -i '/if (mode & ~S_IRWXO)/i \#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)\n\ttrace_ksu_trace_faccessat_hook(&dfd, &filename, &mode, NULL);\n#endif' fs/open.c
        else
            sed -i '/#include "internal.h"/a \#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)\n#include <..\/drivers\/kernelsu\/ksu_trace.h>\n#endif' fs/open.c
            sed -i '/return do_faccessat(dfd, filename, mode);/i\#if defined(CONFIG_KSU) \&\& defined(CONFIG_KSU_TRACEPOINT_HOOK)\n\ttrace_ksu_trace_faccessat_hook(\&dfd, \&filename, \&mode, NULL);\n#endif' fs/open.c
        fi

        if grep -q "trace_ksu_trace_faccessat_hook" "fs/open.c"; then
            echo "[+] fs/open.c Patched!"
            echo "[+] Count: $(grep -c "trace_ksu_trace_faccessat_hook" "fs/open.c")"
        else
            echo "[-] fs/open.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;
    ## read_write.c
    fs/read_write.c)
        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 19 ]; then
            sed -i '/#include <asm\/unistd.h>/a \#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)\n#include <..\/drivers\/kernelsu\/ksu_trace.h>\n#endif' fs/read_write.c
            sed -i '0,/ret = vfs_read(f.file, buf, count, &pos);/ { /ret = vfs_read(f.file, buf, count, &pos);/i \#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)\n\ttrace_ksu_trace_sys_read_hook(fd, &buf, &count);\n#endif
                                           }' fs/read_write.c
        else
            sed -i '/#include <asm\/unistd.h>/a \#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)\n#include <..\/drivers\/kernelsu\/ksu_trace.h>\n#endif' fs/read_write.c
            sed -i '/return ksys_read(fd, buf, count);/i\#if defined(CONFIG_KSU) \&\& defined(CONFIG_KSU_TRACEPOINT_HOOK)\n\ttrace_ksu_trace_sys_read_hook(fd, \&buf, \&count);\n#endif' fs/read_write.c
        fi

        if grep -q "trace_ksu_trace_sys_read_hook" "fs/read_write.c"; then
            echo "[+] fs/read_write.c Patched!"
            echo "[+] Count: $(grep -c "trace_ksu_trace_sys_read_hook" "fs/read_write.c")"
        else
            echo "[-] fs/read_write.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;
    ## stat.c
    fs/stat.c)
        sed -i '/#include <asm\/unistd.h>/a \#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)\n#include <..\/drivers\/kernelsu\/ksu_trace.h>\n#endif' fs/stat.c
        awk '
/error = vfs_fstatat\(dfd, filename, &stat, flag\);/ {
    count++;
    if (count <= 2) {
        print "#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)";
        print "\ttrace_ksu_trace_stat_hook(&dfd, &filename, &flag);";
        print "#endif";
    }
}
{
    print;
}
' fs/stat.c > fs/stat.c.new
        mv fs/stat.c.new fs/stat.c

        if grep -q "trace_ksu_trace_stat_hook" "fs/stat.c"; then
            echo "[+] fs/stat.c Patched!"
            echo "[+] Count: $(grep -c "trace_ksu_trace_stat_hook" "fs/stat.c")"
        else
            echo "[-] fs/stat.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;
    ## namei.c
    fs/namei.c)
        if grep "throne_tracker" "fs/namei.c">/dev/null 2>&1; then
            echo "[-] Warning: fs/namei.c contains KernelSU"
            echo "[+] Code in here:"
            grep -n "throne_tracker" "fs/namei.c"
            echo "[-] End of file."
        elif [ "$FIRST_VERSION" -lt 4 ] && [ "$SECOND_VERSION" -lt 19 ]; then
            sed -i '/if (unlikely(err)) {/a \#ifdef CONFIG_KSU\n\t\tif (unlikely(strstr(current->comm, "throne_tracker"))) {\n\t\t\terr = -ENOENT;\n\t\t\tgoto out_err;\n\t\t}\n#endif' fs/namei.c

            if grep -q "throne_tracker" "fs/namei.c"; then
                echo "[+] fs/namei.c Patched!"
                echo "[+] Count: $(grep -c "throne_tracker" "fs/namei.c")"
            else
                echo "[-] fs/namei.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] Kernel needn't throne_tracker, Skipped."
        fi

        echo "======================================"
        ;;

    # drivers/ changes
    ## input/input.c
    drivers/input/input.c)
        sed -i '/#include "input-compat.h"/a \#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)\n#include <..\/..\/drivers\/kernelsu\/ksu_trace.h>\n#endif' drivers/input/input.c
        sed -i '0,/if (is_event_supported(type, dev->evbit, EV_MAX)) {/ { /if (is_event_supported(type, dev->evbit, EV_MAX)) {/i \#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)\n\ttrace_ksu_trace_input_hook(&type, &code, &value);\n#endif
                                           }' drivers/input/input.c

        if grep -q "trace_ksu_trace_input_hook" "drivers/input/input.c"; then
            echo "[+] drivers/input/input.c Patched!"
            echo "[+] Count: $(grep -c "trace_ksu_trace_input_hook" "drivers/input/input.c")"
        else
            echo "[-] drivers/input/input.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    # security/ changes
    ## security.c
    security/security.c)
        if grep "ksu_handle_setuid" "security/security.c">/dev/null 2>&1; then
            echo "[-] Warning: security/security.c contains KernelSU"
            echo "[+] Code in here:"
            grep -n "ksu_handle" "security/security.c"
            echo "[-] End of file."
        elif [ "$FIRST_VERSION" -lt 4 ] && [ "$SECOND_VERSION" -lt 19 ]; then
            sed -i '/int security_binder_set_context_mgr(struct task_struct/i \#ifdef CONFIG_KSU\n\extern int ksu_bprm_check(struct linux_binprm *bprm);\n\extern int ksu_handle_rename(struct dentry *old_dentry, struct dentry *new_dentry);\n\extern int ksu_handle_setuid(struct cred *new, const struct cred *old);\n\#endif' security/security.c
            sed -i '/ret = security_ops->bprm_check_security(bprm);/i \#ifdef CONFIG_KSU\n\tksu_bprm_check(bprm);\n\#endif' security/security.c
            sed -i '/if (unlikely(IS_PRIVATE(old_dentry->d_inode) ||/i \#ifdef CONFIG_KSU\n\tksu_handle_rename(old_dentry, new_dentry);\n\#endif' security/security.c
            sed -i '/return security_ops->task_fix_setuid(new, old, flags);/i \#ifdef CONFIG_KSU\n\tksu_handle_setuid(new, old);\n\#endif' security/security.c

            if grep -q "ksu_handle_setuid" "security/security.c"; then
                echo "[+] security/security.c Patched!"
                echo "[+] Count: $(grep -c "ksu_handle_setuid" "security/security.c")"
            else
                echo "[-] security/security.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] Kernel needn't setuid, Skipped."
        fi

        echo "======================================"
        ;;
    ## selinux/hooks.c
    security/selinux/hooks.c)
        if [ "$FIRST_VERSION" -lt 4 ] && [ "$SECOND_VERSION" -lt 18 ]; then
            sed -i '/^static int selinux_bprm_set_creds(struct linux_binprm \*bprm)/i \#ifdef CONFIG_KSU\nextern bool is_ksu_transition(const struct task_security_struct *old_tsec,\n\t\t\t\tconst struct task_security_struct *new_tsec);\n#endif' security/selinux/hooks.c
            sed -i '/^\s*new_tsec->exec_sid = 0;/a \#ifdef CONFIG_KSU\n\t\tif (is_ksu_transition(old_tsec, new_tsec))\n\t\t\treturn 0;\n#endif' security/selinux/hooks.c

            if grep -q "is_ksu_transition" "security/selinux/hooks.c"; then
                echo "[+] security/selinux/hooks.c Patched!"
                echo "[+] Count: $(grep -c "is_ksu_transition" "security/selinux/hooks.c")"
            else
                echo "[-] security/selinux/hooks.c patch failed for unknown reasons, please provide feedback in time."
            fi
        elif [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 10 ] && grep -q "grab_transition_sids" "drivers/kernelsu/ksud.c"; then
            sed -i '/^static int check_nnp_nosuid(const struct linux_binprm \*bprm,/i\#ifdef CONFIG_KSU\nextern bool is_ksu_transition(const struct task_security_struct *old_tsec,\n\t\t\t\tconst struct task_security_struct *new_tsec);\n#endif\n' security/selinux/hooks.c
            sed -i '/rc = security_bounded_transition(old_tsec->sid, new_tsec->sid);/i\#ifdef CONFIG_KSU\n\tif (is_ksu_transition(old_tsec, new_tsec))\n\t\treturn 0;\n#endif\n' security/selinux/hooks.c

            if grep -q "is_ksu_transition" "security/selinux/hooks.c"; then
                echo "[+] security/selinux/hooks.c Patched!"
                echo "[+] Count: $(grep -c "is_ksu_transition" "security/selinux/hooks.c")"
            else
                echo "[-] security/selinux/hooks.c patch failed for unknown reasons, please provide feedback in time."
            fi
        elif [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 10 ]; then
            sed -i '/int nnp = (bprm->unsafe & LSM_UNSAFE_NO_NEW_PRIVS);/i\#ifdef CONFIG_KSU\n    static u32 ksu_sid;\n    char *secdata;\n#endif' security/selinux/hooks.c
            sed -i '/if (!nnp && !nosuid)/i\#ifdef CONFIG_KSU\n    int error;\n    u32 seclen;\n#endif' security/selinux/hooks.c
            sed -i '/return 0; \/\* No change in credentials \*\//a\\n#ifdef CONFIG_KSU\n    if (!ksu_sid)\n        security_secctx_to_secid("u:r:su:s0", strlen("u:r:su:s0"), &ksu_sid);\n\n    error = security_secid_to_secctx(old_tsec->sid, &secdata, &seclen);\n    if (!error) {\n        rc = strcmp("u:r:init:s0", secdata);\n        security_release_secctx(secdata, seclen);\n        if (rc == 0 && new_tsec->sid == ksu_sid)\n            return 0;\n    }\n#endif' security/selinux/hooks.c

            if grep -q "security_secid_to_secctx" "security/selinux/hooks.c"; then
                echo "[+] security/selinux/hooks.c Patched!"
                echo "[+] Count: $(grep -c "security_secid_to_secctx" "security/selinux/hooks.c")"
            else
                echo "[-] security/selinux/hooks.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] Kernel needn't selinux fix, Skipped."
        fi

        echo "======================================"
        ;;

    # kernel/ changes
    ## kernel/reboot.c
    kernel/reboot.c)
        if grep -q "ksu_handle_sys_reboot" "drivers/kernelsu/core_hook.c">/dev/null 2>&1; then
            echo "[+] Checked ksu_handle_sys_reboot existed in KernelSU!"

            sed -i '/SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,/i \#ifdef CONFIG_KSU\n\extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\n\#endif' kernel/reboot.c
            sed -i '/int ret = 0;/a \#ifdef CONFIG_KSU\n\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n\#endif' kernel/reboot.c

            if grep -q "ksu_handle_sys_reboot" "kernel/reboot.c"; then
                echo "[+] kernel/reboot.c Patched!"
                echo "[+] Count: $(grep -c "ksu_handle_sys_reboot" "kernel/reboot.c")"
            else
                echo "[-] kernel/reboot.c patch failed for unknown reasons, please provide feedback in time."
            fi
        elif grep -q "ksu_handle_sys_reboot" "drivers/kernelsu/supercalls.c">/dev/null 2>&1; then
            echo "[+] Checked ksu_handle_sys_reboot existed in KernelSU!"

            sed -i '/SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,/i \#ifdef CONFIG_KSU\n\extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\n\#endif' kernel/reboot.c
            sed -i '/int ret = 0;/a \#ifdef CONFIG_KSU\n\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n\#endif' kernel/reboot.c

            if grep -q "ksu_handle_sys_reboot" "kernel/reboot.c"; then
                echo "[+] kernel/reboot.c Patched!"
                echo "[+] Count: $(grep -c "ksu_handle_sys_reboot" "kernel/reboot.c")"
            else
                echo "[-] kernel/reboot.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] KernelSU have no sys_reboot, Skipped."
        fi

        echo "======================================"
        ;;
    ## kernel/sys.c
    kernel/sys.c)
        if grep -q "ksu_handle_setresuid" "drivers/kernelsu/setuid_hook.c" >/dev/null 2>&1; then

            sed -i '/^SYSCALL_DEFINE3(setresuid, uid_t, ruid, uid_t, euid, uid_t, suid)/i\#ifdef CONFIG_KSU\nextern int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid);\n#endif\n' kernel/sys.c
            awk '/kruid = make_kuid\(ns, ruid\);/{count++; if(count==2){print "#ifdef CONFIG_KSU_SUSFS"; print "\t(void)ksu_handle_setresuid(ruid, euid, suid);"; print "#endif"}}1' kernel/sys.c > kernel/sys.c.bak && mv kernel/sys.c.bak kernel/sys.c

            if grep -q "ksu_handle_setresuid" "kernel/sys.c"; then
                echo "[+] kernel/sys.c Patched!"
                echo "[+] Count: $(grep -c "ksu_handle_setresuid" "kernel/sys.c")"
            else
                echo "[-] kernel/sys.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] KernelSU have no ksu_handle_setresuid, Skipped."
        fi

        echo "======================================"
        ;;
    esac

done
