# Posix-shell Service Deployer Template Directory
After building this image with Containerfile, using posix shell with this template is easier to deploy your own service.


## How to Initialize Your Tibero Service

1. First, **COPY THIS DIRECTORY** to where you want to install the Tibero service  
   (You'd better keep using the copied directory to start/stop/manage the installed Tibero service)

2. Place your `license.xml` file (required)
   or other optional Tibero config files inside the [`asset` sub-directory](asset/README.md)

3. Set and customize environment variables for the image inside the `env` file
   (Check for the [.env template](example/env.template) file for more details)

4. Initialize volume first
   ```shell
   ./tbinit
   ```


## How to Deploy Your Tibero Service

Initialize as above first!

- Enable and start the Tibero service
  ```shell
  ./tbenable
  ```

- Show and follow logs of the Tibero service (Press `Ctrl` + `C` key to stop printing logs)
  ```shell
  ./tblogs -f
  ```

- Disable and stop the Tibero service (the container is removed, the volume is not)
  ```shell
  ./tbdisable
  ```

- Cleanup the remaining volume  
  **[!!! WARNING !!!] This command removes ALL DATA (including DB, configs) of the current Tibero service!**
  ```shell
  ./tbremove
  ```

- Repeat above with different ports (by setting `$TB_PORT` as an environment variable or in the `env` file)
  to run multiple Tibero instances on the same host system


## How to Manage Your Tibero Service

- Check current status of the Tibero service
  ```shell
  ./tbstatus
  ```

- Run the `tibero` inner command of the running Tibero service
  ```shell
  ./tibero
  ```


## Abstract of `tibero` Commands (v1.0)

 * Only when the container is running

   - **`tbsql`** *[arg1] [arg2]* ...: Run tbsql as the admin  
        > To run with arguments,  
          just add parameters after the 'tbsql'  
  
     e.g.)  
       `$ podman exec -it <container> tibero tbsql`  
       `$ docker exec -it <container> tibero tbsql id/pw`  
  
       (deployer ver.)  
       `$ ./tibero tbsql id/pw`  
       `$ ./tibero tbsql`  


 * Only when the container is stopped

   - **`init`**: Initialize a Tibero volume  
     e.g.)  
       `$ podman run -it --rm -v <vol>:<mnt-path> <img> init`  
       `$ docker run -it --rm -v <vol>:<mnt-path> <img> init`  
  
   - **`daemon`**: (Default) (Optional) Start a Tibero service with the initialized volume above  
     e.g.)  
       `$ podman run -d -v <vol>:<mnt-path> <img> daemon`  
       `$ docker run -d -v <vol>:<mnt-path> <img>`  


 * Always (on both running and stopped)

   - **`help`**: print this help message  
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
  
       (deployer ver.)  
       `$ ./tibero user create`  
       `$ ./tibero user detail sys`  
       `$ ./tibero user rm`  
