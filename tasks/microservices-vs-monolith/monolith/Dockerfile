FROM node:18-alpine
WORKDIR /app

# Copy only package.json first (for caching layer)
COPY package.json ./
RUN npm install --production

# Copy app source
COPY . .

EXPOSE 3000
CMD ["npm", "start"]
