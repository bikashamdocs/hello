#!/bin/bash

# Set the names and resource group according to your requirements
RESOURCE_GROUP_NAME="rg-ttsazure-lab-dev-techinsights-terraform"
REPLICA_DB_SERVER_NAME="devdb-ti-fx-nreplica-2"
DB_NAME= "ti_dev_db"
REPLICA_DB_SERVER_NAME= "devdb-ti-fx-nreplica-2"
DB_USER_NAME= "tistagingroot"
DB_PASSWORD= "hVRve6*%tXi73!dNb#"

# Get the state of the replica server
state=$(az mysql flexible-server show --resource-group "$RESOURCE_GROUP_NAME" --name "$REPLICA_DB_SERVER_NAME" --query "state" -o tsv)

# Check if the replica server is in the "Stopped" state
if [[ "$state" == "Stopped" ]]; then
    echo "The replica server is in the Stopped state. Starting the server..."
    
    # Start the replica server
    az mysql flexible-server start --name "$REPLICA_DB_SERVER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --verbose -y
fi

echo "Proceeding with replication setup..."

# Start replication on the replica server
mysql -h "$REPLICA_DB_SERVER_NAME".mysql.database.azure.com -u "$DB_USER_NAME" -p'"$DB_PASSWORD"' -e "call mysql.az_replication_start;"

# Check replication status and wait until it catches up with the master (Seconds_Behind_Master is 0)
seconds_behind_master=$(mysql -h "$REPLICA_DB_SERVER_NAME".mysql.database.azure.com -u "$DB_USER_NAME" -p'"$DB_PASSWORD"' -e "show slave status\G;" | awk '/Seconds_Behind_Master/{print $2}')
while [[ $seconds_behind_master -gt 0 ]]
do
    echo "Replication is still catching up. Waiting for the replica to be in sync..."
    sleep 10
    seconds_behind_master=$(mysql -h "$REPLICA_DB_SERVER_NAME".mysql.database.azure.com -u "$DB_USER_NAME" -p'"$DB_PASSWORD"' -e "show slave status\G;" | awk '/Seconds_Behind_Master/{print $2}')
done

echo "Replication is in sync. Stopping replication before backup..."

# Stop replication on the replica server
mysql -h "$REPLICA_DB_SERVER_NAME".mysql.database.azure.com -u "$DB_USER_NAME" -p'"$DB_PASSWORD"' -e "call mysql.az_replication_stop;"

# Check replication status after stopping replication
slave_io_running=$(mysql -h "$REPLICA_DB_SERVER_NAME".mysql.database.azure.com -u "$DB_USER_NAME" -p'"$DB_PASSWORD"' -e "show slave status\G;" | awk '/Slave_IO_Running/{print $2}')
if [[ "$slave_io_running" == "No" ]]
then
    echo "Replication stopped successfully. Proceeding with backup..."

    # Perform the backup using the backups.sh script
    ./backups.sh

    # Stop the replica server
    echo "Backup completed. Stopping the replica server..."
    az mysql flexible-server stop --name "$REPLICA_DB_SERVER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --verbose -y

else
    echo "Failed to stop replication. Please check the replication status and troubleshoot if needed."
fi


