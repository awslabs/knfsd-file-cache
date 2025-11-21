/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"compress/gzip"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestJSONHandler(t *testing.T) {
	type Body struct {
		Message string `json:"msg"`
	}

	execute := func(handler http.Handler, method string) *http.Response {
		req := httptest.NewRequest(method, "/foo", nil)
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, req)
		return w.Result()
	}

	decode := func(res *http.Response) (string, error) {
		r, err := gzip.NewReader(res.Body)
		if err != nil {
			return "", err
		}

		body, err := io.ReadAll(r)
		if err != nil {
			return "", err
		}

		return string(body), nil
	}

	t.Run("response", func(t *testing.T) {
		t.Parallel()
		handler := JSONHandler(func(*http.Request) (*Body, error) {
			return &Body{"Hello World"}, nil
		})
		res := execute(handler, http.MethodGet)
		body, err := decode(res)
		require.NoError(t, err)
		assert.Equal(t, http.StatusOK, res.StatusCode)
		assert.Equal(t, "{\n  \"msg\": \"Hello World\"\n}", body)
	})

	t.Run("nil", func(t *testing.T) {
		t.Parallel()
		handler := JSONHandler(func(*http.Request) (*Body, error) {
			return nil, nil
		})
		res := execute(handler, http.MethodGet)
		body, err := decode(res)
		require.NoError(t, err)
		assert.Equal(t, http.StatusInternalServerError, res.StatusCode)
		assert.Equal(t, `{"message": "An unknown error occurred"}`, body)
	})

	t.Run("error", func(t *testing.T) {
		t.Parallel()
		handler := JSONHandler(func(*http.Request) (*Body, error) {
			return nil, errors.New("handler generated error")
		})
		res := execute(handler, http.MethodGet)
		body, err := decode(res)
		require.NoError(t, err)
		assert.Equal(t, http.StatusInternalServerError, res.StatusCode)
		assert.Equal(t, `{"message": "An unknown error occurred"}`, body)
	})

	t.Run("invalid method", func(t *testing.T) {
		t.Parallel()
		// handlers only allow GET requests
		handler := JSONHandler(func(*http.Request) (*Body, error) {
			return &Body{"Hello World"}, nil
		})
		res := execute(handler, http.MethodPost)
		body, err := decode(res)
		require.NoError(t, err)
		assert.Equal(t, http.StatusMethodNotAllowed, res.StatusCode)
		assert.Equal(t, `{"message": "method not allowed"}`, body)
	})

	t.Run("HEAD request", func(t *testing.T) {
		t.Parallel()
		// should also support HEAD requests for any endpoint that supports GET
		handler := JSONHandler(func(r *http.Request) (*Body, error) {
			return &Body{Message: "Hello World"}, nil
		})
		res := execute(handler, http.MethodHead)
		body, err := decode(res)
		require.NoError(t, err)
		assert.Equal(t, http.StatusOK, res.StatusCode)
		assert.Empty(t, body)
	})
}
