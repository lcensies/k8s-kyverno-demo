POLICY_DIR=policies
TEST_DIR=test

apply:
	kubectl apply -f $(POLICY_DIR)

test:
	kubectl apply -f $(TEST_DIR)/deployment.yaml

clean:
	kubectl delete -f $(TEST_DIR)/deployment.yaml --ignore-not-found
