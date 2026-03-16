POLICY_DIR=policies
TEST_DIR=test

configure:
	@which kubectl || (curl -LO "https://dl.k8s.io/release/$$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl)
	@which helm || (curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash)
	@which minikube || (curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64)

start: configure
	minikube start
	helm repo add kyverno https://kyverno.github.io/kyverno/ || true
	helm repo update
	helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace
	kubectl wait --for=condition=available deployment --all -n kyverno --timeout=120s
	@echo "Waiting for Kyverno webhooks to be ready..."; \
	for i in $$(seq 1 20); do \
		kubectl apply -f $(POLICY_DIR) 2>&1 && break; \
		echo "Retry $$i/20..."; \
		sleep 5; \
	done

apply:
	kubectl apply -f $(POLICY_DIR)

.PHONY: test
test:
	kubectl apply -f $(TEST_DIR)/deployment.yaml

clean:
	kubectl delete -f $(TEST_DIR)/deployment.yaml --ignore-not-found
