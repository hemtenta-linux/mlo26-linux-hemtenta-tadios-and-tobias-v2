# ER diagram for the todo project

The database uses PostgreSQL. The `todos` table stores one row per task. The structure below follows the table definition in `db_setup.py`.

```text
+----------------------------------+
|              todos               |
+----------------------------------+
| PK  id          INTEGER          |
|     title       TEXT             |
|     completed   BOOLEAN          |
+----------------------------------+
```

`PK` means primary key.

| Column      | Data type | Rules                                         | Description                    |
| ----------- | --------- | -------------------------------------------   | ------------------------------ |
| `id`        | `INTEGER` | `PRIMARY KEY`, `GENERATED ALWAYS AS IDENTITY` | Uniquely identifies the task.  |
| `title`     | `TEXT`    | `NOT NULL`                                    | The task's title.              |
| `completed` | `BOOLEAN` | `NOT NULL`, `DEFAULT FALSE`                   | Indicates if the task is done. |

The data model contains one table. When a task is created, PostgreSQL generates its id and uses `FALSE` for its completion status unless another value is provided.

The API also validates titles in `schemas.py`. It removes surrounding whitespace and rejects empty titles and NUL characters. These rules complement the database's `NOT NULL` constraint.

The table is defined in [db_setup.py](../db_setup.py), and the SQL queries are in [db.py](../db.py).

