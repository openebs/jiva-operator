/*
Copyright 2020 The OpenEBS Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package volume

import (
	. "github.com/onsi/ginkgo"
)

var _ = Describe("[csi] [jiva] TEST Remount when volume goes into RO mode", func() {
	BeforeEach(prepareForRemountTest)
	AfterEach(cleanupAfterRemountTest)

	Context("App is deployed and restarted on pvc with replica count 1", func() {
		It("Should run Volume Creation Test", func() { remountTest(PVCName, PVCYAML, DeploymentName, DeployYAML) })
	})
})

func remountTest(pvcName, pvcYAML, deployName, deployYAML string) {
	By("creating and verifying PVC bound status", func() { createAndVerifyPVC(pvcName, pvcYAML) })
	By("Creating and deploying app pod", func() { createDeployVerifyApp(deployName, deployYAML) })
	By("scale down jiva controller pod", scaleDownControllerPod)
	By("Verify app state as CrashLoopBackOff", func() { verifyCrashLoopBackOffStateOfAppPod(deployName, true) })
	By("Scale up jiva controller pod", scaleUpControllerPod)
	By("Verify app state as not CrashLoopBackOff", func() { verifyCrashLoopBackOffStateOfAppPod(deployName, false) })
	By("Deleting application deployment", func() { deleteAppDeployment(deployName, deployYAML) })
	By("Deleting pvc", func() { deletePVC(pvcName, pvcYAML) })
}

func prepareForRemountTest() {
	By("Creating storage class", createStorageClass)
}

func cleanupAfterRemountTest() {
	By("Deleting storage class", deleteStorageClass)
}
