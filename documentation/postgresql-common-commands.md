# Common PostgreSQL commands

## Variables

These commands refer to the following variables, which should be replaced with actual values when executing the commands:

- `DATABASE_HOST`
- `DATABASE_NAME`
- `DATABASE_PASSWORD`
- `DATABASE_PORT`
- `DATABASE_USER`

## Backup or export data

### Plain text SQL statements

```bash
pg_dump -U $DATABASE_USER -W $DATABASE_NAME > backup.sql
```

### Custom binary format

The binary format is suitable for use with `pg_restore`.

```bash
pg_dump -U $DATABASE_USER -p $DATABASE_PORT -Fc $DATABASE_NAME > backup.pgsql
```

## Restore or import data

```bash
PGPASSWORD=$DATABASE_PASSWORD pg_restore -U $DATABASE_USER -h $DATABASE_HOST -p $DATABASE_PORT -d $DATABASE_NAME backup.pgsql
```

## Other useful stuff

### PGPASS file

**TODO**

### Connect to the database container on Daphnis

After SSH'ing to Daphnis, command line tools such as `pg_dump` may be troublesome. Using this command, you can connect directly to the running container and use its command line tools.

```bash
docker exec -it database sh
```
