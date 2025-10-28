#!/bin/bash

################################################################################
# RAM Management Script for macOS
# Purpose: Identify top RAM-consuming processes, allow user selection,
#          terminate selected processes, and display before/after summary
# Compatible with: macOS 10.14+, Terminal, Jamf Self Service
# Author: System Management Team
# Version: 1.1 - Fixed whiptail compatibility
################################################################################

# Exit on any error in pipeline
set -o pipefail

# Dialog configuration
DIALOG_WIDTH=80
DIALOG_HEIGHT=25
DIALOG_LIST_HEIGHT=10

# Temporary file paths
TEMP_DIR="/tmp/ram_manager_$$"
PROCESS_LIST="${TEMP_DIR}/top_processes.txt"
MENU_FILE="${TEMP_DIR}/menu_items.txt"
SELECTION_FILE="${TEMP_DIR}/selections.txt"
SUMMARY_FILE="${TEMP_DIR}/summary.txt"
LOG_FILE="${TEMP_DIR}/ram_manager.log"

################################################################################
# Function: cleanup
# Description: Remove temporary files and exit gracefully
################################################################################
cleanup() {
    rm -rf "${TEMP_DIR}" 2>/dev/null
    exit "${1:-0}"
}

# Set trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

################################################################################
# Function: log_message
# Description: Write timestamped log messages
################################################################################
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

################################################################################
# Function: check_dependencies
# Description: Verify required dialog tools are available
################################################################################
check_dependencies() {
    if command -v dialog &>/dev/null; then
        DIALOG_CMD="dialog"
        log_message "Using dialog for UI"
    elif command -v whiptail &>/dev/null; then
        DIALOG_CMD="whiptail"
        log_message "Using whiptail for UI"
    else
        echo "ERROR: This script requires 'dialog' or 'whiptail'"
        echo "Install via: brew install dialog"
        echo "         or: brew install newt (for whiptail)"
        exit 1
    fi
}

################################################################################
# Function: show_message
# Description: Display informational message box
################################################################################
show_message() {
    local title="$1"
    local message="$2"
    
    if [[ "${DIALOG_CMD}" == "dialog" ]]; then
        dialog --title "${title}" \
               --msgbox "${message}" \
               ${DIALOG_HEIGHT} ${DIALOG_WIDTH}
    else
        whiptail --title "${title}" \
                 --msgbox "${message}" \
                 ${DIALOG_HEIGHT} ${DIALOG_WIDTH}
    fi
    clear
}

################################################################################
# Function: get_ram_usage_mb
# Description: Calculate total RAM usage in MB
# Returns: Integer representing MB of RAM in use
################################################################################
get_ram_usage_mb() {
    # Sum RSS (Resident Set Size) from all processes, convert KB to MB
    ps -caxm -orss= 2>/dev/null | awk '{ sum += $1 } END { printf "%.0f", sum/1024 }'
}

################################################################################
# Function: get_available_memory_mb
# Description: Get available memory from vm_stat
# Returns: Available memory in MB
################################################################################
get_available_memory_mb() {
    local page_size=$(pagesize)
    local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
    echo $(( (pages_free * page_size) / 1048576 ))
}

################################################################################
# Function: fetch_top_processes
# Description: Identify top 10 memory-consuming processes
################################################################################
fetch_top_processes() {
    log_message "Fetching top 10 memory-consuming processes..."
    
    # Get processes with PID, %MEM, RSS (KB), and Command
    # Sort by RSS in descending order, take top 10
    ps aux | awk 'NR>1 {printf "%s|%s|%.1f|%s\n", $2, int($6/1024), $4, substr($0, index($0,$11))}' | \
        sort -t'|' -k2 -rn | head -10 > "${PROCESS_LIST}"
    
    if [[ ! -s "${PROCESS_LIST}" ]]; then
        log_message "ERROR: Failed to retrieve process list"
        show_message "Error" "Unable to retrieve running processes.\nPlease try again."
        cleanup 1
    fi
    
    local process_count=$(wc -l < "${PROCESS_LIST}" | tr -d ' ')
    log_message "Found ${process_count} processes"
}

################################################################################
# Function: build_selection_menu
# Description: Create dialog-compatible menu from process list
################################################################################
build_selection_menu() {
    log_message "Building process selection menu..."
    
    # Build array for whiptail/dialog
    MENU_ITEMS=()
    
    while IFS='|' read -r pid mem_mb mem_pct command; do
        # Truncate long commands to fit dialog width
        if [[ ${#command} -gt 40 ]]; then
            command="${command:0:37}..."
        fi
        
        # Build array: PID "Description" OFF
        MENU_ITEMS+=("${pid}" "${command} (${mem_mb} MB, ${mem_pct}%)" "off")
    done < "${PROCESS_LIST}"
    
    if [[ ${#MENU_ITEMS[@]} -eq 0 ]]; then
        log_message "ERROR: Failed to build menu"
        show_message "Error" "Unable to create process selection menu."
        cleanup 1
    fi
    
    log_message "Menu built with ${#MENU_ITEMS[@]} items"
}

################################################################################
# Function: display_selection_dialog
# Description: Show checklist dialog for process selection
# Returns: 0 if selections made, 1 if cancelled
################################################################################
display_selection_dialog() {
    log_message "Displaying process selection dialog..."
    
    local temp_output="${TEMP_DIR}/dialog_output.txt"
    local exit_status
    
    if [[ "${DIALOG_CMD}" == "dialog" ]]; then
        # Dialog supports --file option and more options
        dialog --stdout \
               --title "RAM Management - Select Processes to Terminate" \
               --checklist "Use SPACE to select, ENTER to confirm, ESC to cancel:" \
               ${DIALOG_HEIGHT} ${DIALOG_WIDTH} ${DIALOG_LIST_HEIGHT} \
               "${MENU_ITEMS[@]}" 2>"${temp_output}"
        exit_status=$?
    else
        # Whiptail requires direct array expansion (no --file option)
        whiptail --title "RAM Management - Select Processes" \
                 --checklist "Use SPACE to select, TAB to move, ENTER to confirm:" \
                 ${DIALOG_HEIGHT} ${DIALOG_WIDTH} ${DIALOG_LIST_HEIGHT} \
                 "${MENU_ITEMS[@]}" 2>"${temp_output}"
        exit_status=$?
    fi
    
    clear
    
    # Handle user cancellation
    if [[ ${exit_status} -ne 0 ]]; then
        log_message "User cancelled operation"
        show_message "Cancelled" "Operation cancelled. No processes were terminated."
        return 1
    fi
    
    # Clean up dialog output (remove quotes and extra spaces)
    cat "${temp_output}" | tr -d '"' | tr -s ' ' '\n' | grep -v '^$' > "${SELECTION_FILE}"
    
    local selection_count=$(wc -l < "${SELECTION_FILE}" | tr -d ' ')
    
    if [[ ${selection_count} -eq 0 ]]; then
        log_message "No processes selected"
        show_message "No Selection" "No processes were selected for termination."
        return 1
    fi
    
    log_message "${selection_count} processes selected for termination"
    return 0
}

################################################################################
# Function: terminate_processes
# Description: Attempt to terminate selected processes
# Populates: TERMINATED_LIST and FAILED_LIST arrays
################################################################################
terminate_processes() {
    log_message "Beginning process termination..."
    
    TERMINATED_LIST=()
    FAILED_LIST=()
    
    while read -r pid; do
        [[ -z "${pid}" ]] && continue
        
        # Get process details before termination attempt
        local proc_info=$(ps -p "${pid}" -o pid=,rss=,comm= 2>/dev/null | \
                         awk '{printf "PID %s: %s (%.0f MB)", $1, $3, $2/1024}')
        
        if [[ -z "${proc_info}" ]]; then
            log_message "Process ${pid} not found (already terminated?)"
            continue
        fi
        
        log_message "Attempting to terminate: ${proc_info}"
        
        # Try graceful termination first (SIGTERM)
        if kill "${pid}" 2>/dev/null; then
            sleep 0.5
            
            # Verify process is gone
            if ! ps -p "${pid}" &>/dev/null; then
                TERMINATED_LIST+=("${proc_info}")
                log_message "Successfully terminated: ${proc_info}"
            else
                # If still running, try forceful termination (SIGKILL)
                if kill -9 "${pid}" 2>/dev/null; then
                    TERMINATED_LIST+=("${proc_info}")
                    log_message "Force-terminated: ${proc_info}"
                else
                    FAILED_LIST+=("${proc_info} (Permission denied)")
                    log_message "Failed to terminate: ${proc_info}"
                fi
            fi
        else
            # Check if failure was due to permissions
            if ps -p "${pid}" &>/dev/null; then
                FAILED_LIST+=("${proc_info} (Insufficient permissions)")
                log_message "Permission denied for: ${proc_info}"
            else
                # Process disappeared between check and kill
                log_message "Process ${pid} terminated externally"
            fi
        fi
    done < "${SELECTION_FILE}"
    
    log_message "Termination complete. Success: ${#TERMINATED_LIST[@]}, Failed: ${#FAILED_LIST[@]}"
}

################################################################################
# Function: generate_summary
# Description: Create before/after summary report
################################################################################
generate_summary() {
    log_message "Generating summary report..."
    
    local ram_freed=$(( RAM_BEFORE_MB - RAM_AFTER_MB ))
    local mem_available_after=$(get_available_memory_mb)
    
    {
        echo "════════════════════════════════════════════════════════════════════════════"
        echo "                       RAM MANAGEMENT SUMMARY                               "
        echo "════════════════════════════════════════════════════════════════════════════"
        echo ""
        echo "RAM USAGE STATISTICS:"
        echo "  Before Operation:  ${RAM_BEFORE_MB} MB"
        echo "  After Operation:   ${RAM_AFTER_MB} MB"
        echo "  RAM Freed:         ${ram_freed} MB"
        echo "  Available Memory:  ${mem_available_after} MB"
        echo ""
        echo "────────────────────────────────────────────────────────────────────────────"
        echo ""
        
        if [[ ${#TERMINATED_LIST[@]} -gt 0 ]]; then
            echo "SUCCESSFULLY TERMINATED PROCESSES (${#TERMINATED_LIST[@]}):"
            for proc in "${TERMINATED_LIST[@]}"; do
                echo "  ✓ ${proc}"
            done
            echo ""
        else
            echo "SUCCESSFULLY TERMINATED PROCESSES: None"
            echo ""
        fi
        
        if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
            echo "FAILED TO TERMINATE (${#FAILED_LIST[@]}):"
            for proc in "${FAILED_LIST[@]}"; do
                echo "  ✗ ${proc}"
            done
            echo ""
            echo "NOTE: Failed terminations may require administrator privileges."
            echo "      Run with 'sudo' or use Activity Monitor with admin rights."
            echo ""
        fi
        
        echo "────────────────────────────────────────────────────────────────────────────"
        echo ""
        echo "Operation completed at: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "Log file: ${LOG_FILE}"
        
    } > "${SUMMARY_FILE}"
    
    log_message "Summary report generated"
}

################################################################################
# Function: display_summary
# Description: Show final summary in text viewer
################################################################################
display_summary() {
    if [[ "${DIALOG_CMD}" == "dialog" ]]; then
        dialog --title "Operation Complete" \
               --textbox "${SUMMARY_FILE}" \
               ${DIALOG_HEIGHT} ${DIALOG_WIDTH}
        clear
    else
        whiptail --title "Operation Complete" \
                 --scrolltext \
                 --textbox "${SUMMARY_FILE}" \
                 ${DIALOG_HEIGHT} ${DIALOG_WIDTH}
        clear
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    # Create temporary directory
    mkdir -p "${TEMP_DIR}"
    
    log_message "=== RAM Management Script Started ==="
    log_message "macOS Version: $(sw_vers -productVersion)"
    log_message "User: $(whoami)"
    
    # Check for required tools
    check_dependencies
    
    # Capture initial RAM usage
    RAM_BEFORE_MB=$(get_ram_usage_mb)
    log_message "Initial RAM usage: ${RAM_BEFORE_MB} MB"
    
    # Show welcome message
    show_message "RAM Management Tool" \
                 "This tool will help you identify and terminate memory-intensive processes.\n\nPress OK to continue."
    
    # Fetch and display top processes
    fetch_top_processes
    build_selection_menu
    
    # Allow user to select processes
    if ! display_selection_dialog; then
        cleanup 0
    fi
    
    # Terminate selected processes
    terminate_processes
    
    # Wait for system to stabilize
    sleep 2
    
    # Capture final RAM usage
    RAM_AFTER_MB=$(get_ram_usage_mb)
    log_message "Final RAM usage: ${RAM_AFTER_MB} MB"
    
    # Generate and display summary
    generate_summary
    display_summary
    
    log_message "=== RAM Management Script Completed ==="
    
    # Display final message
    echo ""
    echo "RAM Management Complete!"
    echo "Log saved to: ${LOG_FILE}"
    echo ""
}

# Execute main function
main
