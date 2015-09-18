# v0.3.0
* Updates for carnivore 1.0
* Remove reel and replace with puma

# v0.2.8
* Set confirmed state directly into message
* Support body on non-200 type responses
* Wait on socket status instead of request status
* Always close connection after confirmation

# v0.2.6
* Add support to disable listen
* Attempt delivery prior to payload persist
* Load payload if possible and deliver via :json

# v0.2.4
* Add fix for memoization issues on init

# v0.2.2
* Add glob support to `:http_path` source
* Allow disabling automatic response on `:http_path`

# v0.2.0
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
