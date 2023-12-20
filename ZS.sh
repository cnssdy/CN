#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN='\033[0m'

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意：请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i"
    if [[ -n $SYS ]]; then
        break
    fi
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
    fi
done

[[ -z $SYSTEM ]] && red "不支持当前VPS系统, 请使用主流的操作系统" && exit 1

check_ip(){
    ipv4=$(curl -s4m8 ip.sb -k | sed -n 1p)
    ipv6=$(curl -s6m8 ip.sb -k | sed -n 1p)
}

inst_acme(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo socat openssl

    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} cronie
        systemctl start crond
        systemctl enable crond
    else
        ${PACKAGE_INSTALL[int]} cron
        systemctl start cron
        systemctl enable cron
    fi

    read -rp "请输入注册邮箱 (例: admin@gmail.com, 或留空自动生成一个gmail邮箱): " email
    if [[ -z $email ]]; then
        automail=$(date +%s%N | md5sum | cut -c 1-16)
        email=$automail@gmail.com
        yellow "已取消设置邮箱, 使用自动生成的gmail邮箱: $email"
    fi

    curl https://get.acme.sh | sh -s email=$email
    source ~/.bashrc
    bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    
    switch_provider

    if [[ -n $(~/.acme.sh/acme.sh -v 2>/dev/null) ]]; then
        green "SSL 一键脚本安装成功!"
    else
        red "抱歉, SSL 一键脚本安装失败"
        green "建议："
        yellow "1. 检查 VPS "

    fi
}

unst_acme() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装Acme.sh, 卸载程序无法执行!" && exit 1
    ~/.acme.sh/acme.sh --uninstall
    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
    rm -rf ~/.acme.sh
    green "Acme.sh 证书一键申请脚本已彻底卸载!"
}

check_80(){
    
    if [[ -z $(type -P lsof) ]]; then
        if [[ ! $SYSTEM == "CentOS" ]]; then
            ${PACKAGE_UPDATE[int]}
        fi
        ${PACKAGE_INSTALL[int]} lsof
    fi
    
    yellow "正在检测 80 端口是否占用..."
    sleep 1
    
    if [[  $(lsof -i:"80" | grep -i -c "listen") -eq 0 ]]; then
        green "检测到目前 80 端口未被占用"
        sleep 1
    else
        red "检测到目前 80 端口被其他程序被占用，以下为占用程序信息"
        lsof -i:"80"
        read -rp "如需结束占用进程请按Y，按其他键则退出 [Y/N]: " yn
        if [[ $yn =~ "Y"|"y" ]]; then
            lsof -i:"80" | awk '{print $2}' | grep -v "PID" | xargs kill -9
            sleep 1
        else
            exit 1
        fi
    fi
}

checktls() {
    if [[ -f /root/cert.crt && -f /root/private.key ]]; then
        if [[ -s /root/cert.crt && -s /root/private.key ]]; then
            if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
                wg-quick up wgcf >/dev/null 2>&1
            fi
            if [[ -a "/opt/warp-go/warp-go" ]]; then
                systemctl start warp-go 
            fi

            echo $domain > /root/ca.log
            sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
            echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab

            green "证书申请成功! 脚本申请到的证书 (cert.crt) 和私钥 (private.key) 文件已保存到 /root 文件夹下"
            yellow "证书 crt 文件路径如下: /root/cert.crt"
            yellow "私钥 key 文件路径如下: /root/private.key"
        else
            if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
                wg-quick up wgcf >/dev/null 2>&1
            fi
            if [[ -a "/opt/warp-go/warp-go" ]]; then
                systemctl start warp-go 
            fi

            red "抱歉，证书申请失败"
            green "建议如下: "
            yellow "1. 自行检测防火墙是否打开, 如使用 80 端口申请模式时, 请关闭防火墙或放行 80 端口"
            yellow "2. 同一域名多次申请可能会触发 Let's Encrypt 官方风控, 请尝试使用脚本菜单的 9 选项更换证书颁发机构, 再重试申请证书, 或更换域名、或等待 7 天后再尝试执行脚本"
            yellow "3. 脚本可能跟不上时代, 建议截图发布到 GitHub Issues、GitLab Issues、论坛或 TG 群询问"
        fi
    fi
}

acme_cfapiTLD(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && inst_acme
    
    check_ip

    read -rp "请输入需要申请证书的域名: " domain
    if [[ $(echo ${domain:0-2}) =~ cf|ga|gq|ml|tk ]]; then
        red "Freenom 免费域名不支持!"
        exit
    fi

    read -rp "请输入 CF API Key: " cfgak
    [[ -z $cfgak ]] && red "未输入 CF API Key, 无法执行操作!" && exit 1
    export CF_Key="$cfgak"
    read -rp "请输入 CF 的登录邮箱: " cfemail
    [[ -z $domain ]] && red "未输入 CF 的登录邮箱, 无法执行操作!" && exit 1
    export CF_Email="$cfemail"
    
    if [[ -z $ipv4 ]]; then
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "${domain}" -k ec-256 --listen-v6 --insecure
    else
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "${domain}" -k ec-256 --insecure
    fi

    bash ~/.acme.sh/acme.sh --install-cert -d "${domain}" --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
    checktls
}

view_cert(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && inst_acme
    bash ~/.acme.sh/acme.sh --list
}

revoke_cert() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && inst_acme

    bash ~/.acme.sh/acme.sh --list
    read -rp "请输入撤销的域名: " domain
    [[ -z $domain ]] && red "未输入域名，无法执行操作!" && exit 1

    if [[ -n $(bash ~/.acme.sh/acme.sh --list | grep $domain) ]]; then
        bash ~/.acme.sh/acme.sh --revoke -d ${domain} --ecc
        bash ~/.acme.sh/acme.sh --remove -d ${domain} --ecc

        rm -rf ~/.acme.sh/${domain}_ecc
        rm -f /root/cert.crt /root/private.key

        green "撤销 ${domain} 的域名证书成功"
    else
        red "未找到 ${domain} 的域名证书, 请检查后重新运行!"
    fi
}

renew_cert() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装SSL, 无法执行操作!" && exit 1
    bash ~/.acme.sh/acme.sh --cron -f
}

switch_provider(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && inst_acme

    yellow "请选择证书提供商, 默认 Let证书 "
    yellow "证书申请失败, 可切换 BuyPass 或 ZeroSSL 来申请."
    echo -e " ${GREEN}1.${PLAIN} Let SSL ${YELLOW}(默认)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} BuyPass"
    echo -e " ${GREEN}3.${PLAIN} ZeroSSL"
    read -rp "请选择证书提供商 [1-3]: " provider
    case $provider in
        2) bash ~/.acme.sh/acme.sh --set-default-ca --server buypass && green "切换证书 BuyPass 成功！" ;;
        3) bash ~/.acme.sh/acme.sh --set-default-ca --server zerossl && green "切换证书 ZeroSSL 成功！" ;;
        *) bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt && green "切换证书 Lets 成功！" ;;
    esac
}

menu() {
    clear
    echo -e "#         ${RED}SSL 一键脚本${PLAIN}                  #"
    echo " -------------"
    echo -e " ${GREEN}1.${PLAIN} 安装 Acme.sh 域名证书申请脚本"
    echo -e " ${GREEN}2.${PLAIN} ${RED}卸载 Acme.sh 域名证书申请脚本${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} 申请单域名证书"
    echo " -------------"
    echo -e " ${GREEN}4.${PLAIN} 查看已申请的证书"
    echo -e " ${GREEN}5.${PLAIN} 撤销并删除已申请的证书"
    echo -e " ${GREEN}6.${PLAIN} 手动续期已申请的证书"
    echo -e " ${GREEN}7.${PLAIN} 切换证书颁发机构"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请输入选项 [0-7]: " menuInput
    case "$menuInput" in
        1 ) inst_acme ;;
        2 ) unst_acme ;;
        3 ) acme_cfapiTLD ;;
        4 ) view_cert ;;
        5 ) revoke_cert ;;
        6 ) renew_cert ;;
        7 ) switch_provider ;;
        * ) exit 1 ;;
    esac
}

menu
