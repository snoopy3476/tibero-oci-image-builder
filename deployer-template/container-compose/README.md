# Compose Service Template Directory
After building this image with Containerfile, using container compose with this template is easier to deploy your own service.


## How to Initialize Your Tibero Service

1. First, **COPY THIS DIRECTORY** to where you want to install the Tibero service  
   (You'd better keep using the copied directory to start/stop/manage the installed Tibero service)

2. Place your `license.xml` file (required)
   or other optional Tibero config files inside the [`asset` sub-directory](asset/README.md)

3. Set and customize environment variables for the image inside the `.env` file
   (Check for the [.env template](example/env.template) file for more details)

4. Select which command to use
   ```
   #############################################################
   ### !!! NOTE: UNCOMMENT ONE OF BELOW YOU WANT TO USE !!!! ###
   #############################################################
   # OCI_CMD="podman"
   # OCI_CMD="docker"
   # OCI_CMD="sudo docker"
   #############################################################

   export PODMAN_COMPOSE_PROVIDER="podman-compose"  # use podman-compose in case of podman
   ```

5. Initialize volume first  
   (The `$OCI_CMD` you chose above is used as the main command)
   ```
   # stop first if the current Tibero service is running
   $OCI_CMD compose down; $OCI_CMD compose -f init.yml down

   # initialize, then remove containers used for the initialization
   $OCI_CMD compose -f init.yml run --rm init || echo " * INIT ERROR * "
   $OCI_CMD compose -f init.yml down

   rm -f asset/account-list  # remove sensitive config data after done
   ```


## How to Deploy Your Tibero Service

Initialize as above first!

- Start the Tibero service
  ```shell
  $OCI_CMD compose up -d
  ```

- Show and follow logs of the Tibero service (Press `Ctrl` + `C` key to stop printing logs)
  ```shell
  $OCI_CMD compose logs -f
  ```

- Stop the Tibero service
  ```shell
  $OCI_CMD compose down
  ```

- Cleanup the remaining volume  
  **[!!! WARNING !!!] This command removes ALL DATA (including DB, configs) of the current Tibero service!**
  ```shell
  $OCI_CMD compose down -v
  $OCI_CMD compose -f init.yml down -v
  ```

- Repeat above with different ports (by setting `$TB_PORT` as an environment variable or in the `.env` file)
  to run multiple Tibero instances on the same host system


## Abstract of `tibero` Commands (v1.1)

 * Only when the container is running

   - **`tbsql`** *[arg1] [arg2]* ...: Run tbsql as the admin  
        > To run with arguments,  
          just add parameters after the 'tbsql'  
  
     e.g.)  
       `$ podman exec -it <container> tibero tbsql`  
       `$ docker exec -it <container> tibero tbsql id/pw`  
  
       (compose ver.)  
       `$ podman-compose exec tb tibero tbsql id/pw`  
       `$ docker compose exec tb tibero tbsql`  


 * Only when the container is stopped

   - **`init`**: Initialize a Tibero volume  
     e.g.)  
       `$ podman run -it --rm -v <vol>:<mnt-path> <img> init`  
       `$ docker run -it --rm -v <vol>:<mnt-path> <img> init`  
  
       (compose ver.)  
       `$ podman-compose -f init.yml run --rm init`  
       `$ docker compose -f init.yml run --rm init`  
  
   - **`daemon`**: (Default) (Optional) Start a Tibero service with the initialized volume above  
     e.g.)  
       `$ podman run -d -v <vol>:<mnt-path> <img> daemon`  
       `$ docker run -d -v <vol>:<mnt-path> <img>`  
  
       (compose ver.)  
       `$ podman-compose run -d`  
       `$ docker compose run -d daemon`  


 * Always (on both running and stopped)

   - **`help`**: print this help message  
   - **`test`**: test if Tibero is running and connectable  
   - **`user`**: manage users  
     - **`ls`**  
     - **`detail`** *[username]*  
     - **`new`**  
     - **`rm`** *[cascade (pass the literal string 'cascade')]*  
     - **`passwd`**  
     - **`lock`** *[username]*  
     - **`unlock`** *[username]*  
     - **`expire`** *[username]*  
  
     e.g.)  
       `$ podman exec -it <container> tibero user create`  
       `$ docker exec -it <container> tibero user detail sys`  
       `$ docker exec -it <container> tibero user rm`  
  
       (compose ver.)  
       `$ podman-compose exec tb tibero user create`  
       `$ docker compose exec tb tibero user detail sys`  
       `$ docker compose exec tb tibero user rm`  
