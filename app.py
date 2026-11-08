# Routes handle HTTP requests, use the database functions in db.py,
# and return data that FastAPI converts into JSON responses.

import db
#import os
import psycopg2
from db_setup import get_connection
from schemas import TodoCreate, TodoUpdate
from contextlib import closing
from fastapi import FastAPI, HTTPException, Response


# Uvicorn's "app:app" loads the app object from this app.py module.
app = FastAPI()


# Each decorator registers an HTTP method and URL path for the function below it.
@app.get("/health")
def health():
    # Monitoring uses this lightweight check to confirm that the API responds.
    return {"status": "ok"}


@app.get("/ready")
def ready():
    try:
        # closing() closes the connection when this block ends, including on errors.
        with closing(get_connection()) as con:
            # The connection context commits on success or rolls back on error.
            with con:
                # The cursor sends SQL to PostgreSQL and closes when its block ends.
                with con.cursor() as cursor:
                    # LIMIT 0 checks table access and column names without fetching rows.
                    cursor.execute("SELECT id, title, completed FROM todos LIMIT 0;")

        return {"status": "ready"}
    except psycopg2.Error:
        # HTTP 503 tells monitoring that the database check failed.
        # The public error message contains a generic description of the failure.
        raise HTTPException(
            status_code=503,
            detail="Database unavailable",
        ) from None

# Register this fixed path before /Todo/{todo_id}, so "list" matches this route.
# GET and PATCH responses use the default successful status code of 200.
@app.get("/Todo/list")
def get_list():
    # Open a separate database connection for this request.
    con = get_connection()

    try:
        # The database function returns all todos ordered by id.
        items = db.get_todos(con)
        # FastAPI converts this dictionary and its list into a JSON response.
        return {"items": items}
    finally:
        # finally runs even after return or an exception, releasing the connection.
        con.close()

# POST creates a resource. HTTP 201 means that creation succeeded.
@app.post("/Todo", status_code=201)
def create_todo(todo: TodoCreate):
    # FastAPI validates the JSON body with TodoCreate before calling this function.
    con = get_connection()

    try:
        # Pass the validated title to the SQL function. PostgreSQL generates the id
        # and supplies completed=False, then returns the newly created row.
        created_todo = db.add_todo(con, todo.title)
        return created_todo
    finally:
        con.close()

# {todo_id} is a path parameter. For /Todo/3, its value is 3.
@app.get("/Todo/{todo_id}")
def read_todo(todo_id: int):
    # The int annotation makes FastAPI reject non-integer ids with HTTP 422.
    con = get_connection()

    try:
        # fetchone() in the database function returns a row or None.
        todo = db.get_todo(con, todo_id)

        # A valid integer can still refer to a missing todo, which gives HTTP 404.
        if todo is None:
            raise HTTPException(
                status_code=404,
                detail="Todo not found",
            )

        return todo
    finally:
        con.close()

# PATCH accepts partial changes to an existing todo.
@app.patch("/Todo/{todo_id}")
def patch_todo(todo_id: int, todo: TodoUpdate):
    # TodoUpdate validates the body, including empty changes and explicit null values.
    con = get_connection()

    try:
        # Omitted fields have the value None. The SQL function uses the current
        # database value for those fields. False is accepted as a new boolean value.
        updated_todo = db.update_todo(
            con,
            todo_id,
            title=todo.title,
            completed=todo.completed,
        )

        # UPDATE ... RETURNING produces no row when the id does not exist.
        if updated_todo is None:
            raise HTTPException(
                status_code=404,
                detail="Todo not found",
            )

        return updated_todo
    finally:
        con.close()


# DELETE removes a resource. HTTP 204 indicates success with an empty response body.
@app.delete("/Todo/{todo_id}", status_code=204)
def remove_todo(todo_id: int):
    con = get_connection()

    try:
        # DELETE ... RETURNING tells us whether a row was actually removed.
        deleted_todo = db.delete_todo(con, todo_id)

        if deleted_todo is None:
            raise HTTPException(
                status_code=404,
                detail="Todo not found",
            )

        # Return an explicit empty response for the 204 status code.
        return Response(status_code=204)
    finally:
        con.close()
