from contextlib import closing

import psycopg2
from fastapi import FastAPI, HTTPException, Response

import db
from db_setup import get_connection
from schemas import TodoCreate

app = FastAPI()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/ready")
def ready():
    try:
        with closing(get_connection()) as con, con, con.cursor() as cursor:
            cursor.execute(
                "SELECT id, title, completed FROM todos LIMIT 0;"
            )

        return {"status": "ready"}

    except psycopg2.Error:
        raise HTTPException(
            status_code=503,
            detail="Database unavailable",
        ) from None

@app.get("/Todo/list")
def get_list():
    with closing(get_connection()) as con:
        return {"items": db.get_todos(con)}


@app.post("/Todo", status_code=201)
def create_todo(todo: TodoCreate):
    with closing(get_connection()) as con:
        return db.add_todo(con, todo.title)


@app.get("/Todo/{todo_id}")
def read_todo(todo_id: int):
    with closing(get_connection()) as con:
        todo = db.get_todo(con, todo_id)

    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")

    return todo


# Change only the title.
@app.patch("/Todo/{todo_id}")
def rename_todo(todo_id: int, todo: TodoCreate):
    with closing(get_connection()) as con:
        updated_todo = db.update_todo(
            con,
            todo_id,
            title=todo.title,
        )

    if updated_todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")

    return updated_todo


# Mark a todo as completed. No request body is needed.
@app.patch("/Todo/{todo_id}/complete")
def complete_todo(todo_id: int):
    with closing(get_connection()) as con:
        updated_todo = db.update_todo(
            con,
            todo_id,
            completed=True,
        )

    if updated_todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")

    return updated_todo


@app.delete("/Todo/{todo_id}", status_code=204)
def remove_todo(todo_id: int):
    with closing(get_connection()) as con:
        deleted_todo = db.delete_todo(con, todo_id)

    if deleted_todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")

    return Response(status_code=204)