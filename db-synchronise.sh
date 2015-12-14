#!/bin/bash
# Script to ease the synchronisation of offline data with online storage of ZEP databases. 

# Usage: put this script in into the zep db/ directory and/or define the source and target by using two input variables:
#'./db-synchronise.sh <SOURCE> <TARGET>'

# When running experiments from different hosts the databases are expected to have a different name under each host. 
# For instance, host IM-lab-phon1 is expected to have the database in db/phone1/
# whereas IM-lab-phon1 is expected to have the database in db/phone2/
# This is not explicity tested by this script. 
# To prevent any irrevertable damage an incremental back-up of the online database is created whenever this synchronisatie is run.
# This incremental backup ignores the database itself and is stored by default in db/synchronisation.backup/.
# To retrieve data herewith saved run this command in the backup directory to inrementally extract the tar.gz's
#  'find -iname '*.tar.gz' | sort | xargs -tL 1 tar --listed-incremental=/dev/null -vxf'

# 2015-12-11 Chris van Run, C.P.A.vanrun@uu.nl, UiL-OTS Utrecht

THIS_SCRIPT_FILENAME="$(basename "$0")"
NUMBER_OF_INPUT_ARGUMENTS="$#"
OPTIONAL_INPUT_ARGUMENT1="$1" #To be source
OPTIONAL_INPUT_ARGUMENT2="$2" #To be target

# Configuration (Global)
BACKUP_DIRECTORY="synchronisation.backup"
SELECTION_START_DIRECTORY="/uilots/"
ZEP_DATABASE_DIRECTORY="db"
WARNING_TEXT="Select a Zep-database directory (\"$ZEP_DATABASE_DIRECTORY\") to synchronise"

# Other Global Variables
SOURCE_DIRECTORY_PATH=""
SOURCE_DIRECTORY=""

TARGET_DIRECTORY_PATH=""
TARGET_DIRECTORY=""

function main() { #input: number of input variables.

    determine_source_and_target

    validate_directory "$SOURCE_DIRECTORY_PATH"
    validate_source_directory_permisisons "$SOURCE_DIRECTORY_PATH"

    validate_directory "$TARGET_DIRECTORY_PATH"
    validate_target_directory_permisisons "$TARGET_DIRECTORY_PATH"

    set_other_global_variables

    make_backup_from_target

    synchronise_and_check_source_and_target

    inform_user_of_completion

    exit 0
}

function determine_source_and_target()
{
    # How many Input arguments are provided?
    case $NUMBER_OF_INPUT_ARGUMENTS in
                    0)
                            set_target_and_source_WITHOUT_command_line_arguments;;
                    2) 
                            set_target_and_source_WITH_command_line_arguments "$OPTIONAL_INPUT_ARGUMENT1" "$OPTIONAL_INPUT_ARGUMENT2" ;;
                    *)
                            handle_error "$NUMBER_OF_INPUT_ARGUMENTS number of command line arguments where given while expecting only 0 or 2."
    esac
}

function set_target_and_source_WITHOUT_command_line_arguments
{
        # Setup and check the current directory.
        SOURCE_DIRECTORY_PATH="$(dirname "$(readlink -f "$0")")"
        SOURCE_DIRECTORY="$(basename "$SOURCE_DIRECTORY_PATH")"

         echo "\"$SOURCE_DIRECTORY_PATH\" has been selected as source."

        # Setup and check the target directory.
        TARGET_DIRECTORY_PATH=$(zenity --file-selection --directory --title="$WARNING_TEXT TOO" --filename="$SELECTION_START_DIRECTORY" --save)
        case $? in
                 0)
                        echo "\"$TARGET_DIRECTORY_PATH\" has been selected as target.";;
                 1)
                        handle_error "No directory selected.";;
                -1)
                        handle_error "An unexpected error has occurred.";;
        esac

        TARGET_DIRECTORY="$(basename "$TARGET_DIRECTORY_PATH")"
}

function set_target_and_source_WITH_command_line_arguments()
{
        SOURCE_DIRECTORY_PATH="$(readlink -f "$1")" #Readlink to convert any relative paths.
        SOURCE_DIRECTORY="$(basename "$SOURCE_DIRECTORY_PATH")"

        TARGET_DIRECTORY_PATH="$(readlink -f "$2")"
        TARGET_DIRECTORY="$(basename "$TARGET_DIRECTORY_PATH")"
}

function validate_directory #Requres input.
{
        if [ ! "$(basename "$1")" = "$ZEP_DATABASE_DIRECTORY" ]; then
                handle_error "\"$1\" is not a valid Zep-database directory ($ZEP_DATABASE_DIRECTORY)! $WARNING_TEXT"
        fi

        if [ ! -d "$1" ]; then
                handle_error "\"$1\" does not seem to be an existing directory!"
        fi
}

function validate_source_directory_permisisons() #Requres input.
{
        if [ ! -r "$1" ]; then
                handle_error "\"$1\" cannot be read from! (Permissions)"
        fi
}

function validate_target_directory_permisisons() #Requres input.
{
        if [ ! -w "$1" ]; then
                handle_error "\"$1\" cannot be written too! (Permissions)"
        fi
}

function set_other_global_variables() #Dependent on Target and source being set prior.
{
    BACKUP_DIRECTORY_PATH="$TARGET_DIRECTORY_PATH/$BACKUP_DIRECTORY"
    SYNCHRONISATION_LOG_FILENAME_PATH="$BACKUP_DIRECTORY_PATH/synchronisation.log"
    SNAPSHOT_FILE_PATH="$BACKUP_DIRECTORY_PATH/$TARGET_DIRECTORY.snapshots"
    START_TIME="$(date +"%F-%H-%M-%S")"
    BACKUP_FILENAME_PATH="$BACKUP_DIRECTORY_PATH/$START_TIME.tar.gz"
}

function make_backup_from_target()
{
        # Setup and/or check the backup directory
        mkdir -p --mode=770 "$BACKUP_DIRECTORY_PATH"

        tar  --no-ignore-case --no-check-device \
        --directory "$(dirname "$TARGET_DIRECTORY_PATH")"  --listed-incremental "$SNAPSHOT_FILE_PATH" --exclude "*$BACKUP_DIRECTORY*" \
        --create --gzip --file "$BACKUP_FILENAME_PATH" "$TARGET_DIRECTORY"
        case "$PIPESTATUS" in
                0)
                        echo "Content in \"$TARGET_DIRECTORY_PATH\" has been backed up in \"$(basename "$BACKUP_DIRECTORY_PATH")\"";;
                *)
                        question_continuation "Could not create a backup copy of target! Tar program failed with error "$PIPESTATUS". Do you want to continue?"
        esac
}

function synchronise_and_check_source_and_target()
{
    USER_UPDATE="Synchronising $SOURCE_DIRECTORY with $TARGET_DIRECTORY..."
    echo "$USER_UPDATE"
    
    rsync --omit-dir-times --times --recursive --human-readable --update --itemize-changes --compress \
    --progress --log-file="$SYNCHRONISATION_LOG_FILENAME_PATH" \
    --chmod=Dug=rwx,Do-rwx,Fug=rw,Fo-rwx \
    --exclude "$THIS_SCRIPT_FILENAME" --exclude "$BACKUP_DIRECTORY" \
    "$SOURCE_DIRECTORY_PATH/" "$TARGET_DIRECTORY_PATH" \
    | tee >(zenity --progress --pulsate --percentage=0 --text="$USER_UPDATE" --auto-close) | xargs --no-run-if-empty -L1 echo

    case "$PIPESTATUS" in
                    0)
                            check_if_synchronisation_was_success;;
                    *)
                            handle_error "Rsync was unsuccesfull in synchronisation. For details run the script via terminal and investigate (std)output!"
    esac
}

function check_if_synchronisation_was_success()
{
    DIFFERENCE=$(rsync -rincu --exclude "$THIS_SCRIPT_FILENAME" --exclude "$BACKUP_DIRECTORY" "$SOURCE_DIRECTORY_PATH/" "$TARGET_DIRECTORY_PATH" | wc -l)
    
    if [ "$PIPESTATUS" -ne 0 ]; then
        handle_error "Could not check if synchronisation was successfull! Rsync error code: "$PIPESTATUS"."
    fi

    if [ "$DIFFERENCE" -ne 0 ]; then
        handle_error "$DIFFERENCE files/directories where not synchronised!"
    fi
}

function inform_user_of_completion()
{
    USER_UPDATE="Synchronised\n\t\"$SOURCE_DIRECTORY_PATH\"\nwith\n\t\"$TARGET_DIRECTORY_PATH\"\n"
    printf  "$USER_UPDATE"
    zenity --info --title="Success!" --text="$USER_UPDATE"
}

function handle_error()
{           
            echo "ERROR! $1"

            if [ "$1" != "" ]; then
                zenity --error --text="$1" --title="Ups ..."
            fi
    
    exit 1
}

function question_continuation()
{
    echo "$1" #For the command line interface
    zenity --window-icon=warning --question --text="$1"

    case "$?" in 
          0) echo "Yes"
          ;; 
          *) handle_error "Canceled."
          ;;
    esac
}

main #see main function at top.