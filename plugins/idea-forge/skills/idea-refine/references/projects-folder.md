<!-- shared file: keep identical to skills/idea-launch/references/projects-folder.md, checked by scripts/check-shared-refs.ps1 -->
# Resolve the projects folder

Every idea-forge skill works inside one **projects folder**. Project folders are created in it as `<projects>/<slug>/`, and the idea pipeline's files go in `<projects>/_idea-forge/<slug>/`. Resolve the folder with these steps before reading or writing anything, and resolve it only once per chat.

## Defaults
- **Windows:** `C:\Projects-Windows`
- **macOS and Linux:** `~/Projects`

The defaults are only suggestions. The user's answer, saved in the config file, always wins.

## The config file
- Path: `<projects>/_idea-forge/config.json`
- Contents: `{"projectsDir": "<absolute path as the user's computer sees it>"}`, for example `{"projectsDir": "D:\\Work\\Projects"}`. Escape backslashes as JSON requires.

The file lives inside the folder it describes, so you can't read it until you've found that folder. Find it by checking the folders that are already connected (step 2).

**The config is found only when the projects folder is connected in the current chat.** In a new chat, either the folder is connected and step 2 finds the config, or it isn't and step 3 asks for the folder again.

## How to reach a folder
- **In the Claude app**, each connected folder is mounted at `$HOME/mnt/<folder name>`. For example, `D:\Work\Projects` is at `$HOME/mnt/Projects`. Use device_bash there.
- **On the computer itself** (Claude Code or local file tools), use the real path.
- To connect a folder, call device_request_folder_access with a short reason that names the step, such as "to save your idea's council verdict". If that tool isn't available, ask the user to add the folder with **+ → Add folder**.

## Steps
1. **Reuse.** If an earlier step in this chat already resolved the projects folder, use it and stop here.
2. **Look for an existing config.** List the connected folders (`ls $HOME/mnt/` in the app). For each one, check for `_idea-forge/config.json`.
   - **Exactly one has it:** read `projectsDir`. If it names this same folder, use it. If it names a different folder, the user has moved the projects folder on purpose. Connect that folder and use it, and if it has no config yet, write one there (step 4).
   - **Several have it:** ask the user which one to use with one AskUserQuestion call.
   - **The config is unreadable or invalid JSON:** say so, and continue as if there were none. Don't overwrite it until the user confirms the folder in step 3.
3. **No config found (first run, or the folder isn't connected in this chat): ask once.** Use one AskUserQuestion call: "Where should idea-forge keep your projects?"
   - Offer first, marked "(Recommended)", the path the user chose before if you know it from this chat or from memory. Otherwise offer the platform default first.
   - If a connected folder looks like a projects folder (it holds an `_idea-forge` folder, or several project folders with `docs/` inside), offer it as well.
   - The user can type any other path.
4. **Save the answer.** Connect the chosen folder if it isn't connected yet, create `_idea-forge/` in it if needed, and write `config.json` with `projectsDir`. Tell the user in one line where idea-forge will keep their projects and how to change it (see below).
5. **If access isn't possible,** keep the work in the chat, say so, and don't write a config anywhere else.

## Changing the folder later
- **The user asks for a different folder** ("use D:\Work instead"): connect the new folder and write a config in its `_idea-forge/`. Then set `projectsDir` in the old config to the new path, so a chat that only has the old folder connected follows the move. Offer to copy the old `_idea-forge/<slug>/` folders across so that earlier ideas stay available. Never delete the old folder.
- **The user edits `projectsDir` by hand:** step 2 picks up the new value the next time any idea-forge skill runs.
- **The user connects a different folder that has its own config:** step 2 finds and uses it. Nothing is cached between chats, so every new chat resolves the folder again.

## In the other skills
Wherever a skill says "the projects folder", it means the folder resolved here. Write paths as `<projects>/<slug>/` and `<projects>/_idea-forge/<slug>/`. When you show the user a path, show the real path on their computer, for example `D:\Work\Projects\kobo-sms-bridge`, not the mount path.
