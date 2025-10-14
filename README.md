# Custom NVM Setup (No Admin Required) on Windows

This guide explains how to set up Node Version Manager (*NVM*) on a Windows corporate laptop without admin privileges, using the portable version of NVM and a custom PowerShell function for `nvm use <version>`.


## 1. Prerequisites

- Windows machine (*corporate laptop with no admin access*)

- PowerShell access (*Command Prompt not supported*)

## 2. Download Required Tools

### 2.1 Download Portable NVM

1. Go to [NVM for Windows GitHub Releases (coreybutler)](https://github.com/coreybutler/nvm-windows/releases)

2. Download the `nvm-noinstall.zip` file (*portable version*)

3. Extract it to `C:\nvm`

### 2.2 Run the portable installer script & configure `settings.txt`

The portable package ships an `install.cmd`. Running it attempts to register values (*writes to registry*) — on a corporate laptop without admin that will often fail, but the script still helps by creating `settings.txt / PATH.txt` samples for you to edit.

#### 1. Run the installer (normal user)

Open a regular (*non-admin*) PowerShell in `C:\nvm` and run:
```console
cd C:\nvm
.\install.cmd
```
- If you see Access to the registry denied — that’s expected on a non-admin machine. The script will then create two files you must edit: `settings.txt` and `PATH.txt`

#### 2. Edit `settings.txt`

Open `C:\nvm\settings.txt` (*create it if not present*) and set the root and path to writable locations. Copy and paste the below settings:
```console
root: C:\nvm\versions
path: C:\nvm\nodejs
arch: 64
proxy: none
```
Notes:
- root is where NVM will download/store Node versions (`C:\nvm\versions`)

- path is where the active node symlink (*or files*) will live (`C:\nvm\nodejs`). You don't have to create `nodejs` folder

- If nvm later complains it cannot find `settings.txt`, confirm that it is in the same folder as `nvm.exe`. If you hit weird parsing errors, try saving lines without extra quotes and ensure there are no stray Unicode characters. (*Rare quirk: some portable builds have shown odd sensitivity to formatting — if you hit trouble, try adding/removing a trailing space at line ends as a quick test.*)
  
#### 3. Inspect `PATH.txt` (what the installer would have set)

If `install.cmd` couldn’t write the system PATH, it will dump a `PATH.txt` showing the PATH it would set. Example PATH.txt content you may see:

```console
PATH=C:\Windows\system32;C:\Windows;...;C:\nvm;...
```
- You do not need to import PATH.txt directly; it’s just a helpful preview

### 2.3 Configure User Environment Variables

Since we don't have admin access, we need to set NVM for your account only:

#### 1. Open **Environment Variables** for your account:

- Press `Win + R`
- Type `rundll32 sysdm.cpl,EditEnvironmentVariables`
- Press `Enter`

#### 2. Under **User variables**, add a new variable:

- **Variable name**: `NVM_HOME`
- **Variable value**: `C:\nvm`
  
#### 3. Also, edit the **Path** user variable and create new value and add:

- `C:\nvm`
 
This allows PowerShell and other terminals to locate `nvm.exe` without requiring admin privileges.

### 2.4 Prepare Node Versions Folder

1. Inside `C:\nvm`, create a folder called `versions`: `C:\nvm\versions`

2. Node versions will be installed inside this folder

### 2.5 Folder Structure Overview

```console
📁 C:\nvm
│
├─ 📄 nvm.exe           # NVM core executable
├─ 📄 settings.txt      # NVM configuration
├─ 📄 PATH.txt          # Installer PATH preview
└─ 📁 versions          # All installed Node versions
    ├─ 📁 v18.17.1
    │   ├─ 📄 node.exe
    │   └─ 📄 ...other files
    ├─ 📁 v20.5.0
    │   ├─ 📄 node.exe
    │   └─ 📄 ...
    └─ 📁 v15.14.0      # Older Node version compatibility
        ├─ 📄 node.exe
        └─ 📄 ...
```
- versions/ — stores all downloaded Node versions

- Older versions (v15 and below) are installed the same way but handled via the PowerShell wrapper to ensure compatibility


## 3. Install Node Versions

1. Open PowerShell

2. Install (*Multiple*) Node Versions:
    ```console
    nvm install 18
    ```
- Note: Versions v15 and below use a separate installation routine for compatibility with older Node releases. The custom PowerShell wrapper handles this automatically


## 4. Configure Custom nvm use (No Admin)

Since corporate laptops don’t allow editing system PATH, we’ll use a PowerShell function to switch Node versions and update User PATH and current session PATH automatically.

### 4.1 Create PowerShell Profile

- Check if your profile exists: `Test-Path $PROFILE`

- If it returns `False`, create it: `New-Item -Path $PROFILE -ItemType File -Force`

- If it returns `True`, you can edit it directly in the next step

### 4.2 Add Custom nvm Function

- Edit your PowerShell profile: `notepad $PROFILE`

- Paste the function provided in the repo (`nvm-function.ps1`) at the end of the file and save.

### 4.3 Load the Profile

- After saving, reload your profile: `. $PROFILE`

- Restart PowerShell (*Optional*)


## 5. Usage

- Switching Node Versions
    ```console
    nvm use 18
    nvm use 20       # Automatically picks latest patch
    nvm use 22.20.0  # Use full version if preferred
    ```

- Checking Node Version
    ```console
    node -v
    ```

- Other NVM Commands
    ```console
    nvm list
    nvm install <node_version>
    nvm uninstall <node_version>
    ```


## 6. Benefits

- Works without admin privileges

- Clean PATH management — no leftover old Node paths

- Supports major version only usage, picks latest patch automatically

- Fully portable, keeps everything in one folder (*C:\nvm*)

- Supports installing and using older Node.js versions seamlessly

<hr>
<hr>