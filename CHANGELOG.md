# V0.2.0
* Add support for message re-delivery and local persistence
* Add support for authorization
* Add HTTPS support
* Add `:http_path` source

# v0.1.8
* Add better message body handling
* Update DSL inclusion on subclasses

# v0.1.6
* Add support for point builder subclassing
* DRY out message generation to be consistent between http and endpoint
* Set max size on body and store in temp file if > max size

# v0.1.4
* Include custom `connect` to start source
* Pull query from body if found
* Fix worker size argument access
* Cleanup point matching implementation

# v0.1.2
* Include query parameters
* Start basic test coverage
* Update message confirmation behavior

# v0.1.0
* Initial release
