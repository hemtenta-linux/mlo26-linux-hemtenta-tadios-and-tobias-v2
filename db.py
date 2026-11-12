from psycopg2.extras import RealDictCursor


def get_items(con):
    with con, con.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute("SELECT * FROM items;")
            items = cursor.fetchall()
    return items

def get_todos(con):
    with con, con.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute("""
                SELECT id, title, completed
                FROM todos
                ORDER BY id;
            """)
            todos = cursor.fetchall()
    return todos

def get_todo(con, todo_id):
    with con, con.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT id, title, completed
                FROM todos
                WHERE id = %s;
                """,
                (todo_id,),
            )
            todo = cursor.fetchone()

    return todo

def add_todo(con, title):
    with con, con.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                INSERT INTO todos (title)
                VALUES (%s)
                RETURNING id, title, completed;
                """,
                (title,),
            )
            todo = cursor.fetchone()


    return todo
# Update the provided fields and preserve existing values for omitted fields.
def update_todo(con, todo_id, title=None, completed=None):
    with con, con.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            UPDATE todos
            SET title = COALESCE(%s, title),
                completed = COALESCE(%s, completed)
            WHERE id = %s
            RETURNING id, title, completed;
            """,
            (title, completed, todo_id),
        )
        todo = cursor.fetchone()

    return todo

def delete_todo(con, todo_id):
    with con, con.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                DELETE FROM todos
                WHERE id = %s
                RETURNING id;
                """,
                (todo_id,),
            )
            deleted_todo = cursor.fetchone()

    return deleted_todo
