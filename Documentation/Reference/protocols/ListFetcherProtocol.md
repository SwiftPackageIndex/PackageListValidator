**PROTOCOL**

# `ListFetcherProtocol`

```swift
public protocol ListFetcherProtocol
```

Fetches an Array of repository URLs from a JSON file.

## Methods
### `listWithSession(_:usingDecoder:_:)`

```swift
func listWithSession<SessionType: Session>(
  _ session: SessionType,
  usingDecoder decoder: JSONDecoder,
  _ completed: @escaping (Result<[URL], Error>) -> Void
)
```

Fetches an Array of repository URLs from a JSON file.
- Parameter session: The Session to build URL requests from.
- Parameter decoder: The JSONDecoder.
- Parameter completed: Callback for when the URLs are decoded.

#### Parameters

| Name | Description |
| ---- | ----------- |
| session | The Session to build URL requests from. |
| decoder | The JSONDecoder. |
| completed | Callback for when the URLs are decoded. |