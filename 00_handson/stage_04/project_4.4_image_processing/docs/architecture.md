# Architecture — Project 4.4 Event-driven Image Processing

## Flow

```
User uploads photo.jpg
  → Storage Account: uploads container
  → Blob trigger fires Azure Function
  → Function reads blob, resizes with Pillow (300x300)
  → Saves thumb_photo.jpg to processed container
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Blob trigger | Function fires on every new blob in container |
| Event Grid | Alternative to blob trigger for more reliable delivery |
| Pillow | Python image processing library |
| Output binding | Write to blob without explicit SDK call |
