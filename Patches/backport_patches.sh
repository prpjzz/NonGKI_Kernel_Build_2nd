#!/bin/bash
# Patches author: backslashxx @ Github
# Shell author: JackA1ltman <cs2dtzq@163.com>
# Tested kernel versions: 5.4, 4.19, 4.14, 4.9, 4.4, 3.18, 3.10, 3.4
# 20250323
patch_files=(
    fs/namespace.c
    fs/internal.h
    include/linux/uaccess.h
    mm/maccess.c
    security/selinux/hooks.c
    security/selinux/selinuxfs.c
    security/selinux/xfrm.c
    security/selinux/include/objsec.h
)

KERNEL_VERSION=$(head -n 3 Makefile | grep -E 'VERSION|PATCHLEVEL' | awk '{print $3}' | paste -sd '.')
FIRST_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $1}')
SECOND_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $2}')

for i in "${patch_files[@]}"; do

    if grep -q "path_umount" "$i"; then
        echo "Warning: $i contains Backport"
        continue
    elif grep -q "selinux_inode" "$i"; then
        echo "Warning: $i contains Backport"
        continue
    elif grep -q "selinux_cred" "$i"; then
        echo "Warning: $i contains Backport"
        continue
    fi

    case $i in

    # fs/ changes
    ## fs/namespace.c
    fs/namespace.c)
        if grep -q "static inline bool may_mandlock(void)" fs/namespace.c; then
            sed -i '/^static bool is_mnt_ns_file/i static int can_umount(const struct path *path, int flags)\n\{\n\tstruct mount *mnt = real_mount(path->mnt);\n\tif (flags & ~(MNT_FORCE | MNT_DETACH | MNT_EXPIRE | UMOUNT_NOFOLLOW))\n\t\treturn -EINVAL;\n\tif (!may_mount())\n\t\treturn -EPERM;\n\tif (path->dentry != path->mnt->mnt_root)\n\t\treturn -EINVAL;\n\tif (!check_mnt(mnt))\n\t\treturn -EINVAL;\n\tif (mnt->mnt.mnt_flags & MNT_LOCKED)\n\t\treturn -EINVAL;\n\tif (flags & MNT_FORCE && !capable(CAP_SYS_ADMIN))\n\t\treturn -EPERM;\n\treturn 0;\n}\n' fs/namespace.c
            sed -i '/^static bool is_mnt_ns_file/i int path_umount(struct path *path, int flags)\n{\n\tstruct mount *mnt = real_mount(path->mnt);\n\tint ret;\n\tret = can_umount(path, flags);\n\tif (!ret)\n\t\tret = do_umount(mnt, flags);\n\tdput(path->dentry);\n\tmntput_no_expire(mnt);\n\treturn ret;\n}\n' fs/namespace.c
        else
            sed -i '/SYSCALL_DEFINE2(umount, char __user \*, name, int, flags)/i\#ifdef CONFIG_KSU\nstatic int can_umount(const struct path *path, int flags)\n{\n\tstruct mount *mnt = real_mount(path->mnt);\n\n\tif (flags & ~(MNT_FORCE | MNT_DETACH | MNT_EXPIRE | UMOUNT_NOFOLLOW))\n\t\treturn -EINVAL;\n\tif (!may_mount())\n\t\treturn -EPERM;\n\tif (path->dentry != path->mnt->mnt_root)\n\t\treturn -EINVAL;\n\tif (!check_mnt(mnt))\n\t\treturn -EINVAL;\n\tif (mnt->mnt.mnt_flags & MNT_LOCKED) /* Check optimistically */\n\t\treturn -EINVAL;\n\tif (flags & MNT_FORCE && !capable(CAP_SYS_ADMIN))\n\t\treturn -EPERM;\n\treturn 0;\n}\n\nint path_umount(struct path *path, int flags)\n{\n\tstruct mount *mnt = real_mount(path->mnt);\n\tint ret;\n\n\tret = can_umount(path, flags);\n\tif (!ret)\n\t\tret = do_umount(mnt, flags);\n\n\t/* we mustn'\''t call path_put() as that would clear mnt_expiry_mark */\n\tdput(path->dentry);\n\tmntput_no_expire(mnt);\n\treturn ret;\n}\n#endif\n' fs/namespace.c
        fi
        ;;
    ## fs/internal.h
    fs/internal.h)
        if grep -q "extern void __mnt_drop_write_file(struct file \*)" fs/internal.h; then
            sed -i '/extern void __mnt_drop_write_file(struct file \*);/a int path_umount(struct path \*path, int flags);' fs/internal.h
        elif grep -q "extern void __init mnt_init(void)" fs/internal.h; then
            sed -i '/extern void __init mnt_init(void);/a int path_umount(struct path *path, int flags);' fs/internal.h
        else
            sed -i '/^extern void __init mnt_init/a int path_umount(struct path *path, int flags);' fs/internal.h
        fi
        ;;

    # include/ changes
    ## include/linux/uaccess.h
    include/linux/uaccess.h)
        if [ "$FIRST_VERSION" -lt 4 ] && [ "$SECOND_VERSION" -lt 18 ] && grep -q "strncpy_from_user_nofault" "drivers/kernelsu/ksud.c"; then
            sed -i '/#endif\t\t\/\* ARCH_HAS_NOCACHE_UACCESS \*\//a long strncpy_from_user_nofault(char *dst, const void __user *unsafe_addr, long count);' include/linux/uaccess.h
        elif grep -q "strncpy_from_user_nofault" "drivers/kernelsu/ksud.c"; then
            sed -i 's/^extern long strncpy_from_unsafe_user/long strncpy_from_user_nofault/' include/linux/uaccess.h
        fi
        ;;

    # mm/ changes
    ## mm/maccess.c
    mm/maccess.c)
        if [ "$FIRST_VERSION" -lt 4 ] && [ "$SECOND_VERSION" -lt 18 ] && grep -q "strncpy_from_user_nofault" "drivers/kernelsu/ksud.c"; then
            cat <<EOF >> mm/maccess.c
long strncpy_from_user_nofault(char *dst, const void __user *unsafe_addr, long count)
{
	mm_segment_t old_fs = get_fs();
	long ret;

	if (unlikely(count <= 0))
		return 0;

	set_fs(USER_DS);
	pagefault_disable();
	ret = strncpy_from_user(dst, unsafe_addr, count);
	pagefault_enable();
	set_fs(old_fs);

	if (ret >= count) {
		ret = count;
		dst[ret - 1] = '\0';
	} else if (ret > 0) {
		ret++;
	}

	return ret;
}
EOF

        elif grep -q "strncpy_from_user_nofault" "drivers/kernelsu/ksud.c"; then
            sed -i 's/\* strncpy_from_unsafe_user: - Copy a NUL terminated string from unsafe user/\* strncpy_from_user_nofault: - Copy a NUL terminated string from unsafe user/' mm/maccess.c
            sed -i 's/long strncpy_from_unsafe_user(char \*dst, const void __user \*unsafe_addr,/long strncpy_from_user_nofault(char *dst, const void __user *unsafe_addr,/' mm/maccess.c
        fi
        ;;

    # security/
    ## selinux/hooks.c
    security/selinux/hooks.c)
        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_inode" "drivers/kernelsu/supercalls.c"; then
            sed -i 's/struct inode_security_struct \*isec = inode->i_security/struct inode_security_struct *isec = selinux_inode(inode)/g' security/selinux/hooks.c
            sed -i 's/return inode->i_security/return selinux_inode(inode)/g' security/selinux/hooks.c
            sed -i 's/\bisec = inode->i_security;/isec = selinux_inode(inode);/' security/selinux/hooks.c
        fi

        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_cred" "drivers/kernelsu/selinux/selinux.c"; then
            sed -i 's/tsec = cred->security;/tsec = selinux_cred(cred);/g' security/selinux/hooks.c
            sed -i 's/const struct task_security_struct \*tsec = cred->security;/const struct task_security_struct *tsec = selinux_cred(cred);/g' security/selinux/hooks.c
            sed -i 's/const struct task_security_struct \*tsec = current_security();/const struct task_security_struct *tsec = selinux_cred(current_cred());/g' security/selinux/hooks.c
            sed -i 's/rc = selinux_determine_inode_label(current_security()/rc = selinux_determine_inode_label(selinux_cred(current_cred())/g' security/selinux/hooks.c
            sed -i 's/old_tsec = current_security();/old_tsec = selinux_cred(current_cred());/g' security/selinux/hooks.c
            sed -i 's/new_tsec = bprm->cred->security;/new_tsec = selinux_cred(bprm->cred);/g' security/selinux/hooks.c
            sed -i 's/rc = selinux_determine_inode_label(old->security/rc = selinux_determine_inode_label(selinux_cred(old)/g' security/selinux/hooks.c
            sed -i 's/tsec = new->security;/tsec = selinux_cred(new);/g' security/selinux/hooks.c
            sed -i 's/tsec = new_creds->security;/tsec = selinux_cred(new_creds);/g' security/selinux/hooks.c
            sed -i 's/old_tsec = old->security;/old_tsec = selinux_cred(old);/g' security/selinux/hooks.c
            sed -i 's/const struct task_security_struct \*old_tsec = old->security;/const struct task_security_struct *old_tsec = selinux_cred(old);/g' security/selinux/hooks.c
            sed -i 's/struct task_security_struct \*tsec = new->security;/struct task_security_struct *tsec = selinux_cred(new);/g' security/selinux/hooks.c
            sed -i 's/__tsec = current_security();/__tsec = selinux_cred(current_cred());/' security/selinux/hooks.c
            sed -i 's/__tsec = __task_cred(p)->security;/__tsec = selinux_cred(__task_cred(p));/' security/selinux/hooks.c
        fi
        ;;
    ## selinux/selinuxfs.c
    security/selinux/selinuxfs.c)
        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_inode" "drivers/kernelsu/supercalls.c"; then
            sed -i 's/(struct inode_security_struct \*)inode->i_security/selinux_inode(inode)/g' security/selinux/selinuxfs.c
        fi
        ;;
    ## selinux/xfrm.c
    security/selinux/xfrm.c)
        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_cred" "drivers/kernelsu/selinux/selinux.c"; then
            sed -i 's/const struct task_security_struct \*tsec = current_security();/const struct task_security_struct *tsec = selinux_cred(current_cred());/g' security/selinux/xfrm.c
        fi
        ;;
    ## selinux/include/objsec.h
    security/selinux/include/objsec.h)
        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_inode" "drivers/kernelsu/supercalls.c"; then
            sed -i '/#endif \/\* _SELINUX_OBJSEC_H_ \*\//i\static inline struct inode_security_struct *selinux_inode(\n\t\t\t\t\t\tconst struct inode *inode)\n{\n\treturn inode->i_security;\n}\n' security/selinux/include/objsec.h
        fi

        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_cred" "drivers/kernelsu/selinux/selinux.c"; then
            sed -i '/#endif \/\* _SELINUX_OBJSEC_H_ \*\//i\static inline struct task_security_struct *selinux_cred(const struct cred *cred)\n{\n\treturn cred->security;\n}\n' security/selinux/include/objsec.h
        fi
        ;;
    esac

done
