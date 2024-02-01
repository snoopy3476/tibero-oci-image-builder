# `pkg` Directory

Place your Tibero package file (`*.tar.gz`) inside the `${IMG_NAME}` sub-directory before running the script `build*.sh`.  
(* Note: the name of the sub-directory becomes the name of the built image!)

## Directory Structure

- `${IMG_NAME}`
  - `${IMG_MINOR_TAG}.tar.gz`  
    Tibero package file: Rename this to what you want as this will be used as a minor tag of built image!
  - `prepared`  
    Tibero configs that are only required and used on building **'prepared ver.'**  
    All files will be processed through `envsubst` command, replacing Tibero container env vars (starting with `$TB_*`) to their actual value of the image  
    (e.g. `This is an example of SID: '${TB_SID}'` -> `This is an example of SID: 'tibero'`
    - `license.xml`  
      License file that is used during the prepared image build
    - `account-list`  
      Tibero user list file to initialize prepared image with
    - `create-db.sql`  
      SQL query file that creates DB, instead of the default implementations  
    - `init.sql`  
      SQL query file that do initialize on created DB  
    - `tip`  
      Tibero tip config file to apply, instead of the default config  
