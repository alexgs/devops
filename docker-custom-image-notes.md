# How to make a custom image

1. Start a base container. This example uses the `node:12` image, but if you're adding to existing image, then you'll want to use that image, like `alexgs99/node:1.2.0`. Remember that the container has to run a command.

```bash
docker run -it node:12
docker ps
docker exec -it a11f7e bash
```

2. Make changes. For example...
  - Change root password with `passwd`
  - Update packages

3. Exit from the bash shell. Commit and push the changes. Here `M.M.P.` is shorthand for versioning numbers `major.minor.patch`.

```bash
docker commit a11f7e alexgs99/node:M.M.P
docker push alexgs99/node:M.M.P
```

4. Update the `latest` tag for your image.

```bash
docker tag alexgs99/node:1.2.0 alexgs99/node:latest
docker push alexgs99/node:latest
```
