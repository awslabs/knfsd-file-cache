/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package log

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/coreos/go-systemd/v22/journal"
)

type any = interface{}

type Logger interface {
	Print(v ...any)
	Printf(format string, v ...any)
}

type SystemdLogger struct {
	Priority journal.Priority
}

func (l *SystemdLogger) Print(v ...any) {
	msg := fmt.Sprint(v...)
	err := journal.Send(msg, l.Priority, nil)
	if err != nil {
		fmt.Printf("Error sending message to systemd journal: %s\n", err)
	}
}

func (l *SystemdLogger) Printf(format string, v ...any) {
	err := journal.Print(l.Priority, format, v...)
	if err != nil {
		fmt.Printf("Error printing message to systemd journal: %s\n", err)
	}
}

type Discard struct{}

func (*Discard) Print(v ...any)                 {}
func (*Discard) Printf(format string, v ...any) {}

type contextKey string

const idKey contextKey = "id"

var (
	useSystemd bool
	Debug      Logger = &Discard{}
	Info       Logger
	Warn       Logger
	Error      Logger
)

// StripPrefixLogger is a custom logger that strips a prefix from messages if present
type StripPrefixLogger struct {
	Logger Logger
	Prefix string
}

func (l *StripPrefixLogger) Print(v ...any) {
	msg := fmt.Sprint(v...)
	l.Logger.Print(stripPrefix(msg, l.Prefix))
}

func (l *StripPrefixLogger) Printf(format string, v ...any) {
	msg := fmt.Sprintf(format, v...)
	l.Logger.Print(stripPrefix(msg, l.Prefix))
}

// stripPrefix removes the prefix from the message if it exists
func stripPrefix(msg, prefix string) string {
	if len(msg) >= len(prefix) && msg[:len(prefix)] == prefix {
		return msg[len(prefix):]
	}
	return msg
}

func init() {
	stderrIsJournalStream, _ := journal.StderrIsJournalStream()
	useSystemd = stderrIsJournalStream && journal.Enabled()

	if useSystemd {
		Info = &SystemdLogger{journal.PriInfo}
		Warn = &SystemdLogger{journal.PriWarning}
		Error = &SystemdLogger{journal.PriErr}
	} else {
		Info = log.New(os.Stderr, "INFO: ", 0)
		Warn = log.New(os.Stderr, "WARN: ", 0)
		// Custom logger that strips the "ERROR: " prefix if already present
		Error = &StripPrefixLogger{
			Logger: log.New(os.Stderr, "ERROR: ", 0),
			Prefix: "ERROR: ",
		}
	}
}

func EnableDebug() {
	if useSystemd {
		Debug = &SystemdLogger{journal.PriDebug}
	} else {
		Debug = log.New(os.Stderr, "DEBUG: ", 0)
	}
}

func WithID(ctx context.Context, id uint64) context.Context {
	return context.WithValue(ctx, idKey, id)
}

func ID(ctx context.Context) uint64 {
	val := ctx.Value(idKey)
	if id, ok := val.(uint64); ok {
		return id
	}
	return 0
}
