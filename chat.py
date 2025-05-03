from openai import OpenAI
from dotenv import load_dotenv
from os import getenv
from random import choice

try:
    load_dotenv()
    print(getenv("BASE_URL"))
    print(getenv("API_KEY"))  
    client = OpenAI(
        base_url = getenv("BASE_URL"),
        api_key = getenv("API_KEY")
    )
    model = client.models.list()
    model = [m.id for m in model]
    print(f"Available models: {model}")
    model = choice(model)
    print(f"Selected '{model}'")
except Exception as e:
    print("Couldn't set up client")
    print(e)
    exit(1)

messages = [{"role": "system", "content": input("Enter system prompt: ")}]

while True:
    prompt = input("> ")
    if prompt in ["exit", "/exit", "quit", "/quit", "bye"]:
        break
    messages.append({"role": "user", "content": prompt})
    response = client.chat.completions.create(
        model = model,
        messages = messages,
    )
    response = response.choices[0].message.content
    messages.append({"role": "assistant", "content": response})
    print(f"🤖 {response}")

for message in mesages:
    prompt = "❓"
    if message["role"] == "system":
        prompt = "⚙️"
    elif message["role"] == "user":
        prompt = "🧑"
    elif message["role"] == "assistant":
        prompt = "🤖"
    print(f"{prompt}: {message['content']}")
