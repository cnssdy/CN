menu() {
    clear
    echo -e "#                   ${RED}SSL 一键脚本${PLAIN}                  #"
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
