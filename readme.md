# Getting started - A suggestion

## FILE STRUCTURE EXPLANATION

- app.py is the main entrypoint which starts fastapi
- db_setup.py contains a function to get a connection to the database, but can also be executed as a script to create some tables (you have to decide which tables)
- db.py should contain functions that simply perform queries and return the result, or raise exceptions when things go wrong. We split things up to keep the app.py file a bit cleaner.
- schemas.py is used for validation, should you decide to use pydantic (HIGHLY RECOMMEND, won't be an option in coming courses)

Ultimately, you can play around with a folder structure if you want to, but we're going to learn a proper structure in our upcoming courses.

## Get started
1. Install the dependencies, e.g (fastapi[standard], psycopg2, python-dotenv) into a virtual environment using pip install -r requirements.txt
2. Create a .env-file and create a DATABASE and PASSWORD variable
3. Make sure you understand how fastapi works
4. Start by creating some tables using the db_setup file
5. Start the api using uvicorn app:app --reload
6. Create some basic endpoints, maybe a basic get which fetches all entries for a table. Test it using postman or the built in swagger interface at localhost:8000/docs
7. Create some basic database-functions that return results from a cursor, your endpoints should utilize these functions
