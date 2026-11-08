# Add Pydantic schemas here that you'll use in your routes / endpoints
# Pydantic schemas are used to validate data that you receive, or to make sure that whatever data
# you send back to the client follows a certain structure

from pydantic import BaseModel, field_validator, model_validator


class TodoCreate(BaseModel):
    title: str

    @field_validator("title")
    @classmethod
    def validate_title(cls, title: str) -> str:
        title = title.strip()

        if not title:
            raise ValueError("Title cannot be empty.")

        if "\x00" in title:
            raise ValueError("Title cannot contain NUL characters.")

        return title

class TodoUpdate(TodoCreate):
    title: str | None = None
    completed: bool | None = None

    @field_validator("title", "completed", mode="before")
    @classmethod
    def reject_null(cls, value):
        if value is None:
            raise ValueError("Fields cannot be null.")

        return value

    @model_validator(mode="after")
    def validate_changes(self):
        if not self.model_fields_set:
            raise ValueError("Provide title or completed.")

        return self
