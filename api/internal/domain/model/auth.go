package model

// SignUpRequest represents a user registration request
// @Description User registration request
type SignUpRequest struct {
	// User's email address
	Email string `json:"email" validate:"required,email,max=254" example:"user@example.com"`
	// User's password (min 8 chars, must contain uppercase, lowercase, number, and special char)
	Password string `json:"password" validate:"required,min=8,max=128" example:"SecureP@ss123"`
}

// SignInRequest represents a user authentication request
// @Description User authentication request
type SignInRequest struct {
	// User's email address
	Email string `json:"email" validate:"required,email,max=254" example:"user@example.com"`
	// User's password
	Password string `json:"password" validate:"required,min=1,max=128" example:"SecureP@ss123"`
}

// ConfirmSignUpRequest represents a sign-up confirmation request
// @Description Sign-up confirmation request with verification code
type ConfirmSignUpRequest struct {
	// User's email address
	Email string `json:"email" validate:"required,email,max=254" example:"user@example.com"`
	// Confirmation code sent to user's email
	ConfirmationCode string `json:"confirmation_code" validate:"required,min=6,max=10,alphanum" example:"123456"`
}

type AuthResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	IdToken      string `json:"id_token,omitempty"`
	ExpiresIn    int32  `json:"expires_in"`
	TokenType    string `json:"token_type"`
}
