package model

type SignUpRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type SignInRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type ConfirmSignUpRequest struct {
	Email            string `json:"email"`
	ConfirmationCode string `json:"confirmation_code"`
}

type AuthResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	IdToken      string `json:"id_token,omitempty"`
	ExpiresIn    int32  `json:"expires_in"`
	TokenType    string `json:"token_type"`
}
