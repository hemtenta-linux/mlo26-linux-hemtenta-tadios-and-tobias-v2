import os

import psycopg2
from dotenv import load_dotenv

load_dotenv()

DATABASE_NAME = os.getenv("DATABASE_NAME")
PASSWORD = os.getenv("PASSWORD")
DATABASE_USER = os.getenv("DATABASE_USER", "postgres")
DATABASE_HOST = os.getenv("DATABASE_HOST", "localhost")
DATABASE_PORT = os.getenv("DATABASE_PORT", "5432")


def get_connection():
    """Öppna en anslutning till databasen."""
    return psycopg2.connect(
        dbname=DATABASE_NAME,
        user=DATABASE_USER,
        password=PASSWORD,
        host=DATABASE_HOST,
        port=DATABASE_PORT,
        connect_timeout=5,
    )


def create_tables():
    """Skapa tabellen todos om den saknas."""
    connection = get_connection()

    try:
        with connection:
            with connection.cursor() as cursor:
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS todos (
                        id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                        title TEXT NOT NULL,
                        completed BOOLEAN NOT NULL DEFAULT FALSE
                    );
                """)
    finally:
        connection.close()


if __name__ == "__main__":
    create_tables()
    print("Tables created successfully.")
