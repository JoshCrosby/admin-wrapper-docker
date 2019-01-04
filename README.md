# General Administration Scripts

Container to wrap scripts that may have unique dependencies (like varying DB versions).

All scripts are run within a temporary container which is removed after execution.

Environment variables can effect how things run:

* `DEBUG=1` - prints out the steps and more debug info
* `ADMIN_SCRIPTS_ENV=a,b,c` - will take `a`, `b`, and `c` as environment variables from the outside environment, and set them on the container's environment
* `EXTERNAL_USER` - set within the container specifying who the external user was that started this
* `EXTERNAL_HOST` - external hostname from where the container is running
* `REFLEX_*` - reflex configs are set matching the external user's reflex information

## Setup

The script `./deploy.sh` can be run as part of a CI action each time a change is made, it copies the `bin/*` files to the outer host; assumedly after container is built and pushed.

It is assumed the container is running in the local repository.  If you want to use a remote repository,
update the REPOS variable in script-container-wrapper.

## Developing

There are two folders: `bin/` and `inside/`:

* `bin/` - put stuff here that is run from the host (outside the container)
* `inside/` - put stuff here that runs within the container.

The name of the script on the inside folder should be linked as a named file within the bin folder, where the link goes to `script-container-wrap` within the same folder.

### example:

1. `bin/admsh` is run from outside the container.
2. It is a link to `scripts-container-wrapper`, which launches the container
3. From within the container `inside/admsh` is run.

The tool to manage the tools (the master process)

* Folder `app/` contains the elixir/phoenix application
* Folder `docker/` contains "build" bits such as for docker and packaging the app up for delivery
* The launch script for dev is `docker/launch-dev`
* It will build static assets (with npm) if `src/assets/node_modules` is missing.

## Developing

The `./local` command is a useful wrapper for docker-compose.  It prints out what it is running, so you can adjust to suite your needs.  You can get a full syntax by just running the command `./local`

It requires the use of `./docker/dev/run.env`.  Reference `./docker/dev/run.env.default` for some defaults which run inside a container -- in this world also enable the container.

### Running

To startup:

	./local dev up --build

This will build and launch the app in docker, running on `localhost:5000`.  If you want to skip docker build and just run the app:

	./local dev up

The folders `docker` and `app` are imported into the container, so it will watch for live changes.

### Connecting a shell / iex

You can connect a shell to your running service with:

	./local dev sh

And from there you can run iex:

	cd src; iex
