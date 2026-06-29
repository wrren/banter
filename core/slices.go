package core

func FirstOrDefault[T any](s []T, def T) T {
	if len(s) == 0 {
		return def
	}
	return s[0]
}
