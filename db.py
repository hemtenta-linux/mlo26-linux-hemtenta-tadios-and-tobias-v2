import psycopg2
from psycopg2.extras import RealDictCursor


"""
This file is responsible for making database queries, which your fastapi endpoints/routes can use.
The reason we split them up is to avoid clutter in the endpoints, so that the endpoints might focus on other tasks 

- Try to return results with cursor.fetchall() or cursor.fetchone() when possible
- Make sure you always give the user response if something went right or wrong, sometimes 
you might need to use the RETURNING keyword to garantuee that something went right / wrong
e.g when making DELETE or UPDATE queries
- No need to use a class here
- Try to raise exceptions to make them more reusable and work a lot with returns
- You will need to decide which parameters each function should receive. All functions 
start with a connection parameter.
- Below, a few inspirational functions exist - feel free to completely ignore how they are structured
- E.g, if you decide to use psycopg3, you'd be able to directly use pydantic models with the cursor, these examples are however using psycopg2 and RealDictCursor
"""

def get_items(con):
    with con:
        with con.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute("SELECT * FROM items;")
            items = cursor.fetchall()
    return items

def get_todos(con):
    with con:
        with con.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute("""
                SELECT id, title, completed
                FROM todos
                ORDER BY id;
            """)
            todos = cursor.fetchall()
    return todos

def get_todo(con, todo_id):
    with con:
        with con.cursor(cursor_factory=RealDictCursor) as cursor:
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
    with con:
        with con.cursor(cursor_factory=RealDictCursor) as cursor:
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

def update_todo(con, todo_id, title=None, completed=None):
    with con:
        with con.cursor(cursor_factory=RealDictCursor) as cursor:
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
    with con:
        with con.cursor(cursor_factory=RealDictCursor) as cursor:
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
