# Ask user to enter region and account ID
# Read sapio_eks_policy_template.json
# Replace "<<<REGION>>>" with the entered region
# Replace "<<<ACCOUNT_ID>>>" with the entered account ID
# Save the modified content to sapio_eks_policy.json


read -r -p "Enter your AWS Account ID (12-digit number): " AWS_ACCOUNT
# auto-remove "-" anywhere in the account ID, if any
AWS_ACCOUNT="${AWS_ACCOUNT//[- ]/}"
if [[ ! $AWS_ACCOUNT =~ ^[0-9]{12}$ ]]; then
    echo "❌ Error: Invalid AWS Account ID. It should be a 12-digit number."
    exit 1
fi
TEMPLATE_FILE="sapio_eks_policy_template.json"
OUTPUT_FILE="sapio_eks_policy.json"
if [[ ! -f $TEMPLATE_FILE ]]; then
    echo "❌ Error: Template file $TEMPLATE_FILE not found!"
    exit 1
fi
# Delete output file if exists
if [[ -f $OUTPUT_FILE ]]; then
    rm "$OUTPUT_FILE"
fi

sed -e "s/<<<ACCOUNT_ID>>>/$AWS_ACCOUNT/g" "$TEMPLATE_FILE" > "$OUTPUT_FILE"
if [[ $? -ne 0 ]]; then
    echo "❌ Error: Failed to create $OUTPUT_FILE."
    exit 1
fi
echo "✅ Successfully created $OUTPUT_FILE with the provided AWS Region and Account ID."
