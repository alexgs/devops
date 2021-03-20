# Custom Node.js DOcker image for local development

## TODO

- [x] Start with Ubuntu LTS base image
- [x] Update packages
- [ ] Install
  - [x] Node.js ^14.x
  - [x] `psql` client ^13.1
  - [x] Zsh
  - [x] Update `npm`
  - [ ] `less`
  - [ ] `sudo`
- [ ] Default entrypoint, probably from the Node.js image
- [ ] Use a `package.json` file to track version numbers for this project
- [ ] Set password for `node` user and make sure it has `sudo` privileges
- [ ] Install for `node` user
  - [ ] Oh My Zsh
    - [ ] Spaceship prompt
    - [ ] Disable upgrade checks
  - [ ] Task

Here's a hash of my usual admin password:
```
$2y$12$c5.ZfEiBNUQSU4xFtsYjpu2YclPKnb1TmQN9V17ZhjS8wIiN8B4lu
```

## References

- https://gist.github.com/trastle/798bfcbbd43a0c0162c9cdc18c4b1a9b
- https://stackoverflow.com/questions/27701930/how-to-add-users-to-docker-container
- https://serverfault.com/questions/773224/how-can-i-set-the-root-password-in-a-docker-container-from-a-script
- https://dev.to/emmanuelnk/using-sudo-without-password-prompt-as-non-root-docker-user-52bg
