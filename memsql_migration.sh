#!/bin/bash 
-x

LOG="/home/memsql/apps/memsql_migration.log"
echo `date` > $LOG
echo "############################### Starting memsql_migration script ###############################" >> $LOG

# Credentials
USERNAME=root    
PASSWORD=poojabhat
SOURCE_SCHEMA=dev
DEST_SCHEMA=qa

SQLFILE=/tmp/sqlfile_`date +%d_%m_%y_%H%M%S`
TABLE_LIST=/tmp/tablelist_`date +%d_%m_%y_%H%M%S`

fn_get_table_list() { 

    echo " " >> $LOG
    echo "Reading control table for list of tables to be processed ..." >> $LOG
    echo " " >>  $LOG

    SQL_TABLE_LIST=$(printf 'select table_name from memsql_mig_ctrl where migration_status="N" order by slno asc;' "$TABLE")
    echo "Following tables will be processed ..." >> $LOG
    echo "$SQL_TABLE_LIST" >> $LOG

    EXEC_TABLE_LIST=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_TABLE_LIST" $SOURCE_SCHEMA` 
    echo "$EXEC_TABLE_LIST" >> $TABLE_LIST
    cat $TABLE_LIST >> $LOG

}

fn_update_ctrl_table() {

    echo " " >> $LOG
    echo "Updating control table for the successful migration of table ..." >> $LOG
    echo " " >>  $Log

    SQL_UPDAGTE_CTRL=$(printf 'update memsql_mig_ctrl set migration_status="Y" where table_name = "%s";' "$TABLE")
    echo "$SQL_UPDAGTE_CTRL" >> $LOG
    EXEC_UPDATE_CTRL=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_UPDAGTE_CTRL" $SOURCE_SCHEMA`

    
}

fn_table_exists() {

    echo " " >> $LOG
    echo "Checking if table exists in source... " >> $LOG
    echo " " >>  $Log

    SQL_EXISTS_IN_SRC=$(printf 'select count(1) from information_schema.tables where table_schema="%s" and table_name="%s";' "$SOURCE_SCHEMA" "$TABLE")
    echo "$SQL_EXISTS_IN_SRC" >> $LOG
    TABLE_EXIST_IN_SRC=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_EXISTS_IN_SRC" $SOURCE_SCHEMA`

    echo " " >> $LOG
    echo "Checking if table exists in destination... " >> $LOG
    echo " " >>  $Log

    SQL_EXISTS_IN_DEST=$(printf 'select count(1) from information_schema.tables where table_schema="%s" and table_name="%s";' "$DEST_SCHEMA" "$TABLE")
    echo "$SQL_EXISTS_IN_DEST" >> $LOG   
    TABLE_EXIST_IN_DEST=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_EXISTS_IN_DEST" $DEST_SCHEMA`

}

fn_is_empty() {

    echo " " >>  $Log
    echo "Checking if table has any records ... " >> $LOG
    echo " " >>  $Log

    SQL_IS_EMPTY=$(printf 'select table_rows from information_schema.tables where table_schema="%s" and table_name="%s";' "$DEST_SCHEMA" "$TABLE")
    echo "$SQL_IS_EMPTY" >> $LOG
    echo "" >> $LOG
    HAS_DATA=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_IS_EMPTY" $DEST_SCHEMA`

}

fn_create_table() {

#Prepare create table statement
        SQL_CREATE_TABLE=$(printf 'show create table %s.%s;' "$SOURCE_SCHEMA" "$TABLE")
        STMT_CREATE_TABLE=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_CREATE_TABLE" $SOURCE_SCHEMA`
        STMT_CREATE_TABLE=`echo "$STMT_CREATE_TABLE" | tr '\n' ' '| sed -e s/$TABLE//1`
        echo $(printf 'use %s;' "$DEST_SCHEMA") > $SQLFILE 
        echo "$STMT_CREATE_TABLE" >> $SQLFILE

#Execute create table statement
        echo " " >>  $Log
        echo "Creating table ..." >> $LOG
        echo " " >> $LOG
        cat $SQLFILE >> $LOG
        EXEC_CREATE_TABLE=`mysql --skip-column-names -u $USERNAME -p$PASSWORD < $SQLFILE`
      
}


fn_create_bkp() {

        echo " " >> $LOG
        echo "Creating table backup ... " >> $LOG
        echo " " >> $LOG
        BKPTABLE=${TABLE}_bkp_`date +%d_%m_%y`
        echo "Bkp table Name: $BKPTABLE" >> $LOG
        echo "" >> $LOG

        SQL_DROP_BKP=$(printf 'drop table if exists %s.%s;' "$DEST_SCHEMA" "$BKPTABLE" )
        SQL_CREATE_BKP=$(printf 'create table if not exists %s.%s select * from %s.%s;' "$DEST_SCHEMA" "$BKPTABLE" "$DEST_SCHEMA" "$TABLE")

        echo " " >> $LOG
        echo "$SQL_DROP_BKP" >> $LOG
        echo " " >> $LOG
        EXEC_DROP_BKP=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_DROP_BKP" $DEST_SCHEMA`

        echo "$SQL_CREATE_BKP" >> $LOG
        echo " " >> $LOG

        EXEC_CREATE_BKP=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_CREATE_BKP" $DEST_SCHEMA`
}


fn_drop_table() {

        echo " " >> $LOG
        echo "Droping existing table ..." >> $LOG
        echo " " >> $LOG


        SQL_DROP_TABLE=$(printf 'drop table if exists %s.%s;' "$DEST_SCHEMA" "$TABLE" )
        echo "$SQL_DROP_TABLE" >> $LOG
        echo " " >> $LOG
        EXEC_DROP_TABLE=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_DROP_TABLE" $DEST_SCHEMA`
}


fn_insert_talble() {

        echo " " >> $LOG
        echo "Loading the new table from backup ..." >> $LOG
        echo " " >> $LOG

#Prepare insert statement
 
 SQL_GET_COLUMNS=$(printf 'select column_name from information_schema.columns where table_schema="%s" and table_name="%s" order by ordinal_position;' "$DEST_SCHEMA" "$TABLE" )

 STMT_GET_COLUMNS=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_GET_COLUMNS" $SOURCE_SCHEMA`
 
 STMT_GET_COLUMNS=`echo "$STMT_GET_COLUMNS" | tr '\n' ',' | sed s/.$//g`

 SQL_INSERT_TABLE=$(printf 'insert into %s.%s select %s from %s.%s;' "$DEST_SCHEMA" "$TABLE" "$STMT_GET_COLUMNS" "$DEST_SCHEMA" "$BKPTABLE")

#Execute insert statement        
        echo " " >> $LOG
        echo "$SQL_INSERT_TABLE" >> $LOG
        echo " " >> $LOG

        EXEC_INSERT_TABLE=`mysql --skip-column-names -u $USERNAME -p$PASSWORD -e "$SQL_INSERT_TABLE" $DEST_SCHEMA`
}



fn_get_table_list

while IFS= read -r line
do

echo " " >> $LOG

# Prepare variables	
TABLE=$line
echo $(printf '********************* Beginning to process Table - %s *********************' "$TABLE")  >> $LOG
echo " " >> $LOG

# Check if table exists
fn_table_exists

if [ $TABLE_EXIST_IN_SRC -eq 1 ]
then

    echo " " >> $LOG
    echo $(printf 'Table %s exists in source schema' "$TABLE")  >> $LOG

    if [ $TABLE_EXIST_IN_DEST -eq 1 ]
    then
    echo $(printf 'Table %s exists in destination schema' "$TABLE") >> $LOG
    echo " " >> $LOG

    # Check if table has records   
    fn_is_empty
 
        if [ $HAS_DATA -gt 0 ]
        then
            echo "Table has records ..." >> $LOG
            echo " " >> $LOG
    
                #Create table backup
                fn_create_bkp
                #Drop existing table
                fn_drop_table
                #Create table
                fn_create_table
                #Load the new table from backup
                fn_insert_talble  
    
        else
            echo "Table is empty ..." >> $LOG
            echo " " >> $LOG
    
                #Drop existing table
                fn_drop_table
                #Create table
                fn_create_table
            
        fi
    else

    echo "Table does not exist ..." >> $LOG
    echo " " >> $LOG
    #Create table
    fn_create_table
    fi

    fn_update_ctrl_table

else

    echo " " >> $LOG
    echo $(printf 'Table %s does not exist in source schema' "$TABLE")  >> $LOG
fi


done < "$TABLE_LIST"

