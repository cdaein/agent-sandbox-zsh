# Agent Sandbox

Run AI coding agents such as Claude Code and Gemini in a Docker container to avoid exposing the whole host file system. I was worried that agents may run rogue code and ruin my machine. A few existing solutions for containerization was too complex for me so I decided to create a simple script. The script will create a reusable Docker image nad a temporary Docker container for each run. It only exposes the current project directory for agents to read and write code. Code editor runs on your host system to give the most flexibility. You can also switch between running the dev server inside the container or on your host system with the same source files.

I set it up to support my Typescript/Nodejs projects. You can customize to meet different needs (See Customization section below).

> IMPORTANT NOTE: this is an experimental personal project and I take no responsibility if things go wrong in any possible way. Use it at your own risk.

## How to use

1. `git clone <this repo>` into wherever you store scripts.
1. Run `<script dir path>/agent-sandbox.zsh <target dir>`
   - For example, `cd` into your project directory, and run `<script dir path>/agent-sandbox.zsh .` (don't forget the dot at the end)
   - If it says no permission, update the execute permission: `chmod +x agent-sandbox.zsh`
1. The script copies a few files into your project directory. (ie. `.dockerignore`, `docker-compose.yml`, `.claude-settings.json`)
1. The script will also build a base Docker image called `agent-sandbox`.
1. If the script exits successfully, run `docker compose run --rm --service-ports dev` to access the container shell.
   - The whole project directory is mounted for the container to access (read and write).
   - It should not have access to files outside the mounted paths.
1. Once you are inside the container zsh shell (indicated by the container ID on the prompt), `npm install` and then `npm run dev -- --host` to run the Vite dev server.
1. To open another shell inside the container, run `docker compose exec -it dev zsh`. Make sure the container IDs are the same.
1. You can use any code editor from your host file system and do everything you need to do while running coding agents within the container.

> Tip: Create an alias in your `.zshrc` to make it easy to use the script. For example, `alias agent-sandbox="~/<script dir>/agent-sandbox/agent-sandbox.zsh"`. Then, `exec zsh` to reload the shell. Now, from anywhere in your system, `agent-sandbox <target dir>` should work.

## Customization

### `/docker-files/base/Dockerfile`

This is where you include any tools you need for all your agent coding projects. Change the Node version you need. Change the shell programs you need. I'm used to working with Oh-My-ZSH so I have it and a few plugins. You can also append (or replace) the default `.zshrc` that omz creates.

### `/docker-files/project/docker-compose.yml`

- This is where you can create project-level configs. I use the Vite dev server and it uses the port `5173`.
- Define any environment variables you need here. It'd be best to `export` these variables in your host and load them in instead of hard-coding the values here to reduce the potential of leaking.
- You can customize the `volumes` and decide what parts of the host file system the container may access.

### Rebuild Docker image

If you made changes to the base image `Dockerfile`, then you will need to rebuild it. `docker image ls` to find the image name. `docker image rm <name>` to delete it.

## Quirks

### `node_modules`

There are packages that install different versions depending on your OS (MacOS vs. Linux). The Docker container runs on Linux while my machine is Mac, meaning when I run `npm i` inside the container, I cannot use the same packages on my host machine (and vice versa). `npm run dev` throws an error. You can try `npm i` again and hopefully, it will install additional packages instead of wholly overriding it. But, if that fails, delete `node_modules` and run `npm i`.

One way to get around this issue is to designate a different node_modules folder for the container. In the project `docker-compose.yml`, Uncomment the volume:

```
    volumes:
      # Persistent container node_modules
      - ./.docker_node_modules:/project/node_modules
```

When you `npm install` inside the container, the packages now go into `.docker_node_modules`. If you use Typescript, update the `tsconfig.json`:

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "*": ["node_modules/*", ".docker_node_modules/*"]
    }
  }
}
```

### Claude Code Authentication

Claude Code doesn't support authenticating with API key (as of 2025.08). So, in a container environment, you have to authenticate using browser and create a new token (and a new api key) every time. To avoid this annoyance, I am copying the `settings.json` that contains the `ANTHROPIC_API_KEY` from the host system. When Claude Code detects this file, it will sign you in. But, this is a hack and this method may not be supported in the future. Hopefully, Anthropic will allow signing in with API key like Gemini already does.

## License

MIT
