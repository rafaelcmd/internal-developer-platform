package main

import "testing"

func TestSplitBrokers(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"", 0},
		{"kafka:9092", 1},
		{"a:9092,b:9092", 2},
		{"  a:9092 , , b:9092  ", 2}, // trims blanks, drops empties
	}
	for _, c := range cases {
		if got := splitBrokers(c.in); len(got) != c.want {
			t.Errorf("splitBrokers(%q) = %v (len %d), want len %d", c.in, got, len(got), c.want)
		}
	}
}
