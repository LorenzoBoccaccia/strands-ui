import uvicorn
from app import app, create_default_admin

if __name__ == "__main__":
    create_default_admin()
    uvicorn.run("app:app", host="0.0.0.0", port=8000, reload=True)
