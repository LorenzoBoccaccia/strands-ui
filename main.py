import subprocess

subprocess.run([
    "gunicorn", "app:app", 
    "--bind", "0.0.0.0:5000", 
    "--workers", "1", 
    "--preload", 
    "-k", "uvicorn.workers.UvicornWorker"
])