/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package connections

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestExtractPeerIP(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		line     string
		expected string
	}{
		{
			name:     "IPv4 address",
			line:     "tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678",
			expected: "10.0.2.100",
		},
		{
			name:     "IPv4 address with different port",
			line:     "tcp   ESTAB 0      0      10.0.1.5:2049 192.168.1.50:12345",
			expected: "192.168.1.50",
		},
		{
			name:     "UDP connection",
			line:     "udp   ESTAB 0      0      10.0.1.5:2049 10.0.2.200:55555",
			expected: "10.0.2.200",
		},
		{
			name:     "IPv6 with brackets",
			line:     "tcp   ESTAB 0      0      [::1]:2049 [2001:db8::1]:45678",
			expected: "2001:db8::1",
		},
		{
			name:     "IPv6 loopback with brackets",
			line:     "tcp   ESTAB 0      0      [::1]:2049 [::1]:45678",
			expected: "::1",
		},
		{
			name:     "empty line",
			line:     "",
			expected: "",
		},
		{
			name:     "insufficient fields",
			line:     "tcp   ESTAB 0      0",
			expected: "",
		},
		{
			name:     "malformed IPv6 brackets",
			line:     "tcp   ESTAB 0      0      [::1]:2049 [2001:db8::1",
			expected: "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			result := extractPeerIP(tc.line)
			assert.Equal(t, tc.expected, result)
		})
	}
}

func TestParseSSOutput(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name            string
		input           string
		expectedEstab   int64
		expectedClients int64
	}{
		{
			name:            "empty output",
			input:           "",
			expectedEstab:   0,
			expectedClients: 0,
		},
		{
			name:            "single ESTAB connection",
			input:           "tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678\n",
			expectedEstab:   1,
			expectedClients: 1,
		},
		{
			name: "multiple ESTAB connections from same client (nconnect scenario)",
			input: `tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45679
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45680
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45681
`,
			expectedEstab:   4,
			expectedClients: 1,
		},
		{
			name: "multiple unique clients all ESTAB",
			input: `tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.101:45678
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.102:45678
`,
			expectedEstab:   3,
			expectedClients: 3,
		},
		{
			name: "mixed: multiple clients with multiple ESTAB connections each",
			input: `tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45679
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.101:52341
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.101:52342
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.101:52343
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.102:33333
`,
			expectedEstab:   6,
			expectedClients: 3,
		},
		{
			name: "TCP and UDP mixed",
			input: `tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678
udp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45679
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.101:45678
`,
			expectedEstab:   3,
			expectedClients: 2,
		},
		{
			name: "nconnect=16 simulation for single client",
			input: `tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45679
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45680
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45681
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45682
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45683
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45684
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45685
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45686
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45687
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45688
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45689
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45690
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45691
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45692
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45693
`,
			expectedEstab:   16,
			expectedClients: 1,
		},
		{
			name: "TIME-WAIT connections only (no ESTAB)",
			input: `tcp   TIME-WAIT 0      0      10.0.1.5:2049 10.0.2.100:45678
tcp   TIME-WAIT 0      0      10.0.1.5:2049 10.0.2.100:45679
tcp   TIME-WAIT 0      0      10.0.1.5:2049 10.0.2.101:52341
`,
			expectedEstab:   0,
			expectedClients: 2,
		},
		{
			name: "mixed ESTAB and TIME-WAIT from different clients",
			input: `tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45679
tcp   TIME-WAIT 0      0      10.0.1.5:2049 10.0.2.101:52341
tcp   TIME-WAIT 0      0      10.0.1.5:2049 10.0.2.101:52342
tcp   TIME-WAIT 0      0      10.0.1.5:2049 10.0.2.102:33333
`,
			expectedEstab:   2,
			expectedClients: 3,
		},
		{
			name: "mixed states: ESTAB, TIME-WAIT, CLOSE-WAIT, FIN-WAIT-2",
			input: `tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678
tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45679
tcp   TIME-WAIT 0      0      10.0.1.5:2049 10.0.2.101:52341
tcp   CLOSE-WAIT 0      0      10.0.1.5:2049 10.0.2.102:33333
tcp   FIN-WAIT-2 0      0      10.0.1.5:2049 10.0.2.103:44444
`,
			expectedEstab:   2,
			expectedClients: 4,
		},
		{
			name: "idle client with only TIME-WAIT (recently active)",
			input: `tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678
tcp   TIME-WAIT 0      0      10.0.1.5:2049 10.0.2.101:52341
`,
			expectedEstab:   1,
			expectedClients: 2,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			counts, err := parseSSOutput([]byte(tc.input))
			require.NoError(t, err)
			assert.Equal(t, tc.expectedEstab, counts.established, "established count mismatch")
			assert.Equal(t, tc.expectedClients, counts.clients, "clients count mismatch")
		})
	}
}
