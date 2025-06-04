/*
	Copyright 2024 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package stage

import (
	"examples/testing"

	scope "github.com/gruntwork-io/terratest/modules/test-structure"
)

func RunApply(t testing.TestingT, f func()) {
	scope.RunTestStage(t, "apply", f)
}

func RunValidate(t testing.TestingT, f func()) {
	scope.RunTestStage(t, "validate", f)
}

func RunDestroy(t testing.TestingT, f func()) {
	scope.RunTestStage(t, "destroy", f)
}
