#!/bin/bash

#================================================================
#               COLOR & STYLE DEFINITIONS
#================================================================
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
BLUE=$(tput setaf 4)
NC=$(tput sgr0) # No Color

#================================================================
#               HELPER AND CORE FUNCTIONS
#================================================================

wait_for_user() {
    echo
    read -p "${BLUE}Press [Enter] to return to the main menu...${NC}"
}

restart_and_check_service() {
    echo
    echo "🔄 ${YELLOW}Restarting tunnelmonitor service...${NC}"
    if sudo systemctl restart tunnelmonitor.service; then
		echo "✅ ${GREEN}Service restarted successfully.${NC}"
		echo "🔎 ${YELLOW}Displaying service status:${NC}"
		local a_state=$(systemctl show -p ActiveState --value tunnelmonitor.service)
		local s_state=$(systemctl show -p SubState --value tunnelmonitor.service)
		echo "   ${GREEN}Current Status: ${a_state} (${s_state})${NC}"
	else
		echo "❌ ${RED}ERROR: Failed to restart service.${NC}"
		echo "🔎 ${YELLOW}Displaying recent errors from logs:${NC}"
		sudo journalctl -u tunnelmonitor.service -n 10 --no-pager 
	fi
}

# --- Prerequisites function now includes 'jq' for reading config files ---
install_prerequisites() {
    echo "🔄 ${YELLOW}Updating system package list...${NC}"
    sudo apt-get update -y >/dev/null 2>&1
    echo "🐍 ${YELLOW}Installing prerequisites (pip, unzip, jq)...${NC}"
    sudo apt-get install -y python3-pip unzip jq >/dev/null 2>&1
    
    echo "🤖 ${YELLOW}Installing Python Telegram Bot library...${NC}"
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [ "$ID" = "ubuntu" ]; then sudo pip3 install python-telegram-bot >/dev/null 2>&1;
        elif [ "$ID" = "debian" ]; then sudo pip3 install --break-system-packages python-telegram-bot >/dev/null 2>&1;
        else sudo pip3 install python-telegram-bot >/dev/null 2>&1; fi
    else sudo pip3 install python-telegram-bot >/dev/null 2>&1; fi
    echo "✅ ${GREEN}All prerequisites are installed.${NC}"
}

# --- Setup functions now prompt for edit before starting the service ---
setup_master() {
    local source_dir="$1"
    local target_dir="/opt/tunnelmonitor"
    echo "🚀 Starting Master setup..."
    
    echo "📂 Copying files from '$source_dir' to '$target_dir'..."
    sudo mkdir -p "$target_dir"
    sudo cp -r "$source_dir"/* "$target_dir"/

    if [ -f "$target_dir/run_all.sh" ]; then
        echo "🔒 Setting execute permissions for run_all.sh..."
        sudo chmod +x "$target_dir/run_all.sh"
    fi
    
    echo "🔧 Setting up systemd service definition..."
    if [ ! -f "$target_dir/tunnelmonitor.service" ]; then
        echo "❌ ${RED}Error: 'tunnelmonitor.service' not found!${NC}"; return 1
    fi
    sudo cp "$target_dir/tunnelmonitor.service" /etc/systemd/system/tunnelmonitor.service
    sudo systemctl daemon-reload

    # =================== بخش جدید برای انتخاب نوع کانفیگ ===================
    echo "-----------------------------------------"
    echo "🔧 Configuration Step"
    echo "How do you want to provide the configuration?"
    echo "   1) Configure manually now"
    echo "   2) Restore from a backup"
    read -p "Your choice [1-2]: " config_choice

    if [ "$config_choice" = "2" ]; then
        # اگر کاربر بازگردانی را انتخاب کرد، تابع مربوطه را فراخوانی می‌کنیم
        # این تابع خودش سرویس را در انتها ری‌استارت می‌کند
        run_restore_backup
    else
        # در غیر این صورت (انتخاب ۱ یا هر ورودی دیگر)، به روش دستی ادامه می‌دهیم
        if [ "$config_choice" != "1" ]; then
            echo "Invalid choice. Defaulting to manual configuration."
        fi
        echo "🔵 ${YELLOW}Please edit the configuration files.${NC}"
        read -p "Press [Enter] to edit config.json..."
        sudo nano "$target_dir/config.json"
        read -p "Press [Enter] to edit master_config.json..."
        sudo nano "$target_dir/master_config.json"

        echo "▶️  Enabling and starting the service for the first time..."
        restart_and_check_service
    fi
    # ===================== پایان بخش جدید =====================

    echo "✅ ${GREEN}Master setup complete!${NC}"
	wait_for_user
    return 0
}

setup_client() {
    local source_dir="$1"
    local target_dir="/opt/Client"
    echo "🚀 Starting Client setup..."

    echo "📂 Copying files from '$source_dir' to '$target_dir'..."
    sudo mkdir -p "$target_dir"
    sudo cp -r "$source_dir"/* "$target_dir"/

    echo "🔧 Setting up systemd service definition..."
    if [ ! -f "$target_dir/tunnelmonitor.service" ]; then
        echo "❌ ${RED}Error: 'tunnelmonitor.service' not found!${NC}"; return 1
    fi
    sudo cp "$target_dir/tunnelmonitor.service" /etc/systemd/system/tunnelmonitor.service
    sudo systemctl daemon-reload
    
    # =================== بخش جدید برای انتخاب نوع کانفیگ ===================
    echo "-----------------------------------------"
    echo "🔧 Configuration Step"
    echo "How do you want to provide the configuration?"
    echo "   1) Configure manually now"
    echo "   2) Restore from a backup"
    read -p "Your choice [1-2]: " config_choice

    if [ "$config_choice" = "2" ]; then
        # فراخوانی تابع بازگردانی بکاپ
        run_restore_backup
	else
        # در غیر این صورت، ادامه به روش دستی
        if [ "$config_choice" != "1" ]; then
            echo "Invalid choice. Defaulting to manual configuration."
        fi
        echo "🔵 ${YELLOW}Please edit the configuration file.${NC}"
        read -p "Press [Enter] to edit config.json..."
        sudo nano "$target_dir/config.json"

		echo "▶️  Enabling and starting the service for the first time..."
		restart_and_check_service
    fi
    # ===================== پایان بخش جدید =====================

    echo "✅ ${GREEN}Client setup complete!${NC}"
	wait_for_user
    return 0
}

run_installer() {
    clear; echo "--- Installation TunnelCheker ---"
    if [ -d "/opt/tunnelmonitor" ] || [ -d "/opt/Client" ]; then
        echo "⚠️ ${YELLOW}Application is already installed. Uninstall first.${NC}"; wait_for_user; return
    fi
    local GITHUB_URL="https://github.com/Eslender73/telegram_TunnelCheker/raw/refs/heads/main/TunnelCheker.zip"
    echo "🌐 ${YELLOW}Downloading TunnelCheker.zip from GitHub...${NC}"
    
    # ابتدا اگر فایل قدیمی وجود دارد آن را حذف می‌کنیم
    rm -f ./TunnelCheker.zip

    # با دستور wget فایل را دانلود کرده و در صورت خطا، خارج می‌شویم
    if ! wget -q --show-progress -O ./TunnelCheker.zip "$GITHUB_URL"; then
        echo "❌ ${RED}Error: Failed to download TunnelCheker.zip.${NC}"
        wait_for_user
        return
    fi
    tput cuu1
    tput el
    echo "✅ ${GREEN}Download complete.${NC}"
    # --- پایان بخش جدید ---

    if ! install_prerequisites; then
        echo "❌ ${RED}Halting due to errors in prerequisite setup.${NC}"; wait_for_user; return
    fi

    TEMP_DIR="/tmp/TunnelCheker_install"
    echo "📦 Extracting files from TunnelCheker.zip..."
    sudo rm -rf "$TEMP_DIR"; mkdir -p "$TEMP_DIR"
    if ! sudo unzip -qo ./TunnelCheker.zip -d "$TEMP_DIR"; then
        echo "❌ ${RED}Failed to extract zip file.${NC}"; sudo rm -rf "$TEMP_DIR"; wait_for_user; return
    fi
    
    local source_base_path="$TEMP_DIR"
    if [ -d "$TEMP_DIR/TunnelCheker" ]; then
        source_base_path="$TEMP_DIR/TunnelCheker"
    fi

    echo "------------------------"
    echo "Which part to install?" 
	echo "1) Master" 
	echo "2) Client"
    read -p "Choice: " choice
    
    local setup_success=false
    case $choice in
        1)
            if [ ! -d "$source_base_path/master" ]; then echo "❌ ${RED}Error: 'master' folder not found!${NC}";
            elif setup_master "$source_base_path/master"; then setup_success=true; fi ;;
        2)
            if [ ! -d "$source_base_path/Client" ]; then echo "❌ ${RED}Error: 'Client' folder not found!${NC}";
            elif setup_client "$source_base_path/Client"; then setup_success=true; fi ;;
        *) echo "${RED}Invalid choice.${NC}";;
    esac

# این بلوک کد باید در انتهای تابع run_installer و قبل از wait_for_user قرار گیرد

    if [ "$setup_success" = true ]; then
        # بررسی می‌کنیم که آیا فایل منیجر در سورس وجود دارد
        if [ -f "$source_base_path/manager.sh" ]; then
            echo "⚙️  ${YELLOW}Making the management script a global command...${NC}"
            
            # ۱. از cp به جای mv برای امنیت بیشتر استفاده می‌کنیم
            sudo cp "$source_base_path/manager.sh" /usr/local/bin/manager
            
            # ۲. اطمینان حاصل می‌کنیم که دستور جدید قابل اجراست
            sudo chmod +x /usr/local/bin/manager
			echo "🧹 Cleaning up temporary files..."
			sudo rm -rf "$TEMP_DIR"
            echo "✅ ${GREEN}Management script installed successfully.${NC}"
            
            # ۳. متغیر رنگ را به BLUE (بزرگ) و غلط املایی را تصحیح می‌کنیم
            echo "✅ ${RED}To run the manager from anywhere, type 'manager' in your console.${NC}"
        fi
        
        # این خط از نسخه‌های قبلی باقی‌مانده و دیگر نیازی به آن نیست
        # restart_and_check_service 
    fi
    wait_for_user
}

run_uninstaller() {
    clear; echo "--- Uninstall Utility ---"
    INSTALL_DIR=""
    IS_MASTER=false # یک پرچم برای تشخیص نوع نصب

    # تشخیص نوع و مسیر نصب
    if [ -d "/opt/tunnelmonitor" ]; then
        INSTALL_DIR="/opt/tunnelmonitor"
        IS_MASTER=true
    elif [ -d "/opt/Client" ]; then
        INSTALL_DIR="/opt/Client"
    fi

    if [ -z "$INSTALL_DIR" ]; then
        echo "❌ ${RED}Error: No installation found.${NC}"; wait_for_user; return
    fi

    # سوال اصلی برای تایید حذف
    read -p "⚠️  ${YELLOW}This will permanently delete all application files. Are you sure? [y/N]:${NC} " confirm
    if [[ ! "$confirm" =~ ^[yY](es)?$ ]]; then
        echo "Uninstall cancelled."; wait_for_user; return
    fi


    # =================== بخش جدید برای پشتیبان‌گیری از کانفیگ ===================
    local keep_configs=""
    # بر اساس نوع نصب، سوال مناسب را می‌پرسیم
    if [ "$IS_MASTER" = true ]; then
        read -p "❓ ${YELLOW}Do you want to save config files (config.json, master_config.json, message_id.txt)? [y/N]:${NC} " keep_configs
    else
        read -p "❓ ${YELLOW}Do you want to save the config file (config.json)? [y/N]:${NC} " keep_configs
    fi

    # اگر کاربر تایید کرد، فایل‌ها را کپی می‌کنیم
    if [[ "$keep_configs" =~ ^[yY](es)?$ ]]; then
        # ساخت پوشه پشتیبان در مسیر خانگی کاربر با تاریخ و ساعت دقیق
        local backup_dir="$HOME/tunnelmonitor_backup/$(date +%F_%H-%M-%S)"
        echo "🔄 ${YELLOW}Backing up config files to ${backup_dir}...${NC}"
        mkdir -p "$backup_dir"

        # کپی کردن فایل‌ها بر اساس نوع نصب
        if [ "$IS_MASTER" = true ]; then
            sudo cp "$INSTALL_DIR/config.json" "$backup_dir/" 2>/dev/null
            sudo cp "$INSTALL_DIR/master_config.json" "$backup_dir/" 2>/dev/null
            sudo cp "$INSTALL_DIR/message_id.txt" "$backup_dir/" 2>/dev/null
        else
            sudo cp "$INSTALL_DIR/config.json" "$backup_dir/" 2>/dev/null
        fi

        # تغییر مالکیت فایل‌های کپی شده به کاربر فعلی (برای دسترسی آسان)
        sudo chown -R $USER:$USER "$backup_dir"
        echo "✅ ${GREEN}Backup complete.${NC}"
    fi
    # ===================== پایان بخش جدید =====================


    echo "🗑️  Uninstalling application...";
    sudo systemctl stop tunnelmonitor.service >/dev/null 2>&1
    sudo systemctl disable tunnelmonitor.service >/dev/null 2>&1
    sudo rm -f /etc/systemd/system/tunnelmonitor.service
    sudo systemctl daemon-reload
    sudo rm -rf "$INSTALL_DIR"
    echo "✅ ${GREEN}Uninstallation complete.${NC}"
    wait_for_user
}

run_editor() {
    clear; echo "--- Configuration Editor ---"
    if [ -d "/opt/tunnelmonitor" ]; then
        echo "🔑 Master detected. Which file to edit?"; echo "1) config.json"; echo "2) master_config.json"
        read -p "Choice: " choice
        case $choice in
            1) sudo nano /opt/tunnelmonitor/config.json; restart_and_check_service ;;
            2) sudo nano /opt/tunnelmonitor/master_config.json; restart_and_check_service ;;
            *) echo "${RED}Invalid choice.${NC}" ;;
        esac
    elif [ -d "/opt/Client" ]; then
        echo "💻 Client detected. Opening config.json..."; sudo nano /opt/Client/config.json; restart_and_check_service
    else echo "❌ ${RED}Error: No installation found.${NC}";
    fi
    wait_for_user
}

run_restore_backup() {
    clear
    echo "--- Restore Backup ---"

    # مرحله ۱: بررسی اینکه آیا برنامه اصلا نصب است یا خیر
    local INSTALL_DIR=""
    if [ -d "/opt/tunnelmonitor" ]; then
        INSTALL_DIR="/opt/tunnelmonitor"
    elif [ -d "/opt/Client" ]; then
        INSTALL_DIR="/opt/Client"
    else
        echo "❌ ${RED}Error: Application is not installed. Cannot restore backup.${NC}"
        wait_for_user
        return
    fi

    local main_backup_dir="$HOME/tunnelmonitor_backup"

    # مرحله ۲: بررسی اینکه آیا پوشه‌ی بکاپ یا خود بکاپی وجود دارد
    if [ ! -d "$main_backup_dir" ] || [ -z "$(ls -A "$main_backup_dir")" ]; then
        echo "❌ ${RED}No backups found in ${main_backup_dir}.${NC}"
        wait_for_user
        return
    fi

    # مرحله ۳: نمایش لیست بکاپ‌های موجود و دریافت انتخاب از کاربر
    echo "🔎 ${YELLOW}Available backups:${NC}"
    
    # از یک آرایه برای ذخیره مسیر بکاپ‌ها استفاده می‌کنیم
    declare -a backups=()
    local i=1
    
    # حلقه برای نمایش تمام پوشه‌های بکاپ
    for backup_path in "$main_backup_dir"/*/; do
        local backup_name=$(basename "$backup_path") # گرفتن نام پوشه (همان تاریخ)
        echo "   $i) $backup_name"
        backups+=("$backup_path") # اضافه کردن مسیر کامل به آرایه
        ((i++))
    done

    echo
    read -p "Please choose a backup to restore [1-$(($i-1))]: " choice

    # مرحله ۴: اعتبارسنجی انتخاب کاربر
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -ge "$i" ]; then
        echo "❌ ${RED}Invalid choice.${NC}"
        wait_for_user
        return
    fi

    # مرحله ۵: انجام بازگردانی
    # از آرایه، مسیر بکاپ انتخاب شده را برمی‌داریم (اندیس آرایه از ۰ شروع می‌شود)
    local selected_backup="${backups[$choice-1]}"
    
    echo "🔄 ${YELLOW}Restoring files from $(basename "$selected_backup")...${NC}"
    
    # فایل‌های داخل پوشه بکاپ را به مسیر نصب کپی می‌کنیم
    if sudo cp -v "$selected_backup"* "$INSTALL_DIR/"; then
        echo "✅ ${GREEN}Backup restored successfully.${NC}"
        
        # مرحله ۶: ری‌استارت کردن سرویس
        restart_and_check_service
    else
        echo "❌ ${RED}An error occurred during the restore process.${NC}"
    fi
}
run_restore_backup_menu() {
    clear
    echo "--- Restore Backup ---"

    # مرحله ۱: بررسی اینکه آیا برنامه اصلا نصب است یا خیر
    local INSTALL_DIR=""
    if [ -d "/opt/tunnelmonitor" ]; then
        INSTALL_DIR="/opt/tunnelmonitor"
    elif [ -d "/opt/Client" ]; then
        INSTALL_DIR="/opt/Client"
    else
        echo "❌ ${RED}Error: Application is not installed. Cannot restore backup.${NC}"
        wait_for_user
        return
    fi

    local main_backup_dir="$HOME/tunnelmonitor_backup"

    # مرحله ۲: بررسی اینکه آیا پوشه‌ی بکاپ یا خود بکاپی وجود دارد
    if [ ! -d "$main_backup_dir" ] || [ -z "$(ls -A "$main_backup_dir")" ]; then
        echo "❌ ${RED}No backups found in ${main_backup_dir}.${NC}"
        wait_for_user
        return
    fi

    # مرحله ۳: نمایش لیست بکاپ‌های موجود و دریافت انتخاب از کاربر
    echo "🔎 ${YELLOW}Available backups:${NC}"
    
    # از یک آرایه برای ذخیره مسیر بکاپ‌ها استفاده می‌کنیم
    declare -a backups=()
    local i=1
    
    # حلقه برای نمایش تمام پوشه‌های بکاپ
    for backup_path in "$main_backup_dir"/*/; do
        local backup_name=$(basename "$backup_path") # گرفتن نام پوشه (همان تاریخ)
        echo "   $i) $backup_name"
        backups+=("$backup_path") # اضافه کردن مسیر کامل به آرایه
        ((i++))
    done

    echo
    read -p "Please choose a backup to restore [1-$(($i-1))]: " choice

    # مرحله ۴: اعتبارسنجی انتخاب کاربر
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -ge "$i" ]; then
        echo "❌ ${RED}Invalid choice.${NC}"
        wait_for_user
        return
    fi

    # مرحله ۵: انجام بازگردانی
    # از آرایه، مسیر بکاپ انتخاب شده را برمی‌داریم (اندیس آرایه از ۰ شروع می‌شود)
    local selected_backup="${backups[$choice-1]}"
    
    echo "🔄 ${YELLOW}Restoring files from $(basename "$selected_backup")...${NC}"
    
    # فایل‌های داخل پوشه بکاپ را به مسیر نصب کپی می‌کنیم
    if sudo cp -v "$selected_backup"* "$INSTALL_DIR/"; then
        echo "✅ ${GREEN}Backup restored successfully.${NC}"
        
        # مرحله ۶: ری‌استارت کردن سرویس
        restart_and_check_service
    else
        echo "❌ ${RED}An error occurred during the restore process.${NC}"
    fi
	wait_for_user
}
#================================================================
#                       MAIN MENU & LOOP
#================================================================
while true; do
    clear
    # --- Server and Service Status ---
    SERVER_TYPE="Not Installed"; SERVICE_STATUS="Not Found"; STATUS_COLOR=$RED; CONFIG_PATH=""
    if [ -d "/opt/tunnelmonitor" ]; then SERVER_TYPE="Master"; CONFIG_PATH="/opt/tunnelmonitor/config.json";
    elif [ -d "/opt/Client" ]; then SERVER_TYPE="Client"; CONFIG_PATH="/opt/Client/config.json"; fi
    if systemctl is-active --quiet tunnelmonitor.service; then
        SERVICE_STATUS="Active"; STATUS_COLOR=$GREEN
    elif systemctl list-units --full -all | grep -q "tunnelmonitor.service"; then
        SERVICE_STATUS="Inactive/Failed"
    fi
    
    echo "================================================"
    echo "      Tunnel Monitor Unified Manager"
    echo "================================================"
    echo -e "Server Type: ${YELLOW}${SERVER_TYPE}${NC}"
    echo -e "Service Status: ${STATUS_COLOR}${SERVICE_STATUS}${NC}"
    echo "------------------------------------------------"

    # --- Display Server Info from config.json ---
    if [ -f "$CONFIG_PATH" ]; then
        SERVER_NAME=$(jq -r '.CLname' "$CONFIG_PATH" 2>/dev/null)
        SERVER_IP=$(jq -r '.CLipv4' "$CONFIG_PATH" 2>/dev/null)
        TUNNEL_COUNT=$(jq '.ID_ip4_ip6_name | length' "$CONFIG_PATH" 2>/dev/null)
        
        echo "    ${BLUE}📋 Server Info Dashboard${NC}"
        echo "    - Server Name: ${GREEN}${SERVER_NAME:-N/A}${NC}"
        echo "    - Server IP:   ${GREEN}${SERVER_IP:-N/A}${NC}"
        # The key in your JSON was "ID_ip4/ip6_name", jq needs quotes for the slash
        TUNNEL_COUNT=$(jq '.["ID_ip4/ip6_name"] | length' "$CONFIG_PATH" 2>/dev/null)
        echo "    - Tunnels Monitored: ${GREEN}${TUNNEL_COUNT:-0}${NC}"
        echo "------------------------------------------------"
	
    echo "    ${BLUE}🔍 Monitored Tunnels Details${NC}"
    
    # از یک حلقه while و دستور printf برای فرمت‌بندی کاملاً تراز شده استفاده می‌کنیم
    jq -r '.["ID_ip4/ip6_name"][] | split(",") | "\(.[1])|\(.[2])"' "$CONFIG_PATH" | while IFS='|' read -r ip name; do
        # حذف فاصله‌های اضافی احتمالی از ابتدا و انتهای متغیرها
        ip=$(echo "$ip" | xargs)
        name=$(echo "$name" | xargs)

        # استفاده از printf برای چاپ با فاصله‌بندی دقیق
        # %-42s به این معنی است که متغیر اول (IP) در فضایی به عرض 42 کاراکتر و با چینش چپ قرار می‌گیرد
        printf "    - IP: ${GREEN}%-42s${NC} | Name: ${GREEN}%s${NC}\n" "$ip" "$name"
    done
    
    echo "------------------------------------------------"

    fi

    # ======== منوی اصلی اصلاح شده ========
	echo "   1) Install TunnelCheker "
	echo "   2) Edit Configuration "
	echo "   3) Uninstall TunnelCheker "
	echo "   4) Restore Backup" # <--- گزینه جدید
	echo "   5) Exit " # <--- شماره جدید
	echo
# ... (خطوط echo برای نمایش منو اینجا قرار دارند)


    # دستور خواندن ورودی از کاربر
    read -p "Please enter your choice [1-5]: " main_choice

    # این خط برای شروع دستور case ضروری است
    case $main_choice in
        1) 
            run_installer 
            ;;
        2) 
            run_editor 
            ;;
        3) 
            run_uninstaller 
            ;;
        4) 
            run_restore_backup_menu 
            ;;
        5) 
            clear; echo "Goodbye!"; exit 0 
            ;;
        *) 
            echo "${RED}Invalid option. Please try again.${NC}"; sleep 1 
            ;;
    
    # این خط برای پایان دستور case ضروری است
    esac
done