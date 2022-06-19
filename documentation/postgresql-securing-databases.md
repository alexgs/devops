# Securing PostgreSQL Databases

:boom: **WARNING** :boom: PostreSQL is weird about case sensitivity. The best solution is to use lower case for all database and role names. If you insist on using upper case, you _must_ wrap database and role names in double quotes.

You can use the following commands to secure a PostgreSQL database. These instructions assume you are connected to the cluster with the `psql` command line tool.

## Variables

These commands refer to the following variables, which should be replaced with actual values when executing the commands:

- `DATABASE_NAME`
- `DATABASE_PASSWORD`
- `DATABASE_USER`

## Commands

All of these commands assume that they are being run by an administrator account.

### Create a user or group

PostgreSQL treats both users and groups as "roles".

```sql
CREATE ROLE $DATABASE_USER
  WITH LOGIN PASSWORD '$DATABASE_PASSWORD';
```

### Remove access privileges

For a new database, this command should be repeated for each existing user or role in the cluster that does not need access (i.e. principle of least privilege).

```sql
REVOKE ALL ON DATABASE $DATABASE_NAME
  FROM $DATABASE_USER;
```

### Grant access privileges

For a new database, this will grant access for only the user(s) that will access the database (i.e. principle of least privilege). The "Create" privilege is required for installing extensions during migrations in some projects.

```sql
GRANT CONNECT, CREATE ON DATABASE $DATABASE_NAME
  TO $DATABASE_USER;
```

### Restrict public access to existing tables

```sql
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
```

### Grant one user access to existing tables

```sql
GRANT ALL ON ALL TABLES IN SCHEMA public TO $DATABASE_USER;
```

### Grant one user access to future tables

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DATABASE_USER;
```

### Allow one user to create new databases

This command is needed, for example, to enable the [shadow database][1] used by Prisma 2.25 and later. It may not be necessary if your project is using Prisma's `migrate` feature or Flyway.

[1]: https://www.prisma.io/docs/concepts/components/prisma-migrate/shadow-database

```sql
ALTER ROLE $DATABASE_USER WITH CREATEDB;
```
