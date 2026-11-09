package generate

// SetAfterWrite installs a hook that runs between Generate writing its entries
// and re-reading what they were made from, and returns a func that removes it.
func SetAfterWrite(f func()) (restore func()) {
	afterWrite = f
	return func() { afterWrite = nil }
}
