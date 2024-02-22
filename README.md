# Tibero OCI Image Builder

- OCI image (e.g. `podman` or `docker` image) builder which builds a new Tibero 6 or Tibero 7 Linux image, by providing any Tibero `*.tar.gz` file
- Build both normal version (initialize manually) & prepared version (initialized to a specific account)


## How to Use

1. Place `tar.gz file` (Tibero installation package) inside the `pkg/${IMG_NAME}` directory
   - Refer to [the README.md file in the `pkg` directory](pkg/README.md)
2. (Optional) Place the related inside the `asset` directory to make them the 'image default config', according to your needs
   - Refer to [the README.md file in the `asset` directory](asset/README.md)
3. Build image using `build-all.sh`
   - For building only the normal image (not prepared ver), `build.sh` can also be used
4. Deploy your image using one of templates in `deployer-template` directory
   - Refer to the README.md file of each template [in the `deployer-template`](deployer-template)


## Structure of Image from the Builder

### Filesystem structure

- `/opt/tibero`: Tibero service account home
  - `tibero-home`: Tibero binary home
  - `persistable`: Tibero persistable data, to be stored in volumes
    - `database`: Tibero database data
    - `config`: Tibero config data
      - `license`: Tibero license directory
      - `sql`: Tibero custom SQL directory
      - `tip`: Tibero tip file directory
  - `persistable-defaults`: Image initial default of the Tibero persistable data above

### Tibero accounts

- OS account (main local admin account)
  - `OSA${TB_SID}`
    - DBA (admin)
    - Cannot access remotely, only for local access
    - Use this account with `tbsql /` inside the tibero container
      - Run with `podman` or `docker` as follows:
        - `podman exec -it <container> tbsql /`
        - `docker exec -it <container> tbsql /`
- Tibero system accounts
  - `SYS`, `SYSCAT`, `SYSGIS`, `OUTLN`
    - Passwords are set randomly
    - Do not use this directly and use OS account above instead for administration purpose, unless you really need them for some usecase
- User account
  - Not created by default unless `./asset/account-list` file exists: image users are prompted to enter username and password on start


## Abstract of `tibero` Commands (v1.1)

You can utilize `tibero` command inside the image, on both running Tibero container or a new one


 * Only when the container is running

   - **`tbsql`** *[arg1] [arg2]* ...: Run tbsql as the admin  
        > To run with arguments,  
          just add parameters after the 'tbsql'  
  
     e.g.)  
       `$ podman exec -it <container> tibero tbsql`  
       `$ docker exec -it <container> tibero tbsql id/pw`  


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
